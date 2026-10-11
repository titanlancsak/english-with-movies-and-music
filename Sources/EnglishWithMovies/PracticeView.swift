import AVFoundation
import LinguaCore
import SwiftUI

/// Sheet for practicing one subtitle line: listen, record, get a score.
struct PracticeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var practice: PracticeStore
    @EnvironmentObject private var phonemes: PhonemeEngine
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceRecorder()
    let line: TranscriptLine

    enum Phase: Equatable {
        case idle
        case recording
        case analyzing
        case result(PronunciationResult)
        case failed(String)
    }

    @ViewState private var phase: Phase = .idle
    @ViewState private var recording: URL?
    @ViewState private var playback: AVAudioPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel(text: "Treino de pronúncia")
                    Text("Pratique a fala")
                        .font(.system(size: 26, weight: .heavy))
                        .gradientForeground()
                }
                Spacer()
                if let source = model.sourceName {
                    Chip(text: "\(source) · \(formatTime(line.start))", systemImage: "film", color: Theme.textDim)
                        .lineLimit(1)
                        .frame(maxWidth: 260, alignment: .trailing)
                }
            }

            Text(line.text)
                .font(.system(size: 21, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.indigo.opacity(0.25), Theme.violet.opacity(0.12)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
                .textSelection(.enabled)

            controls
            content

            if phonemes.state != .ready {
                SoundsSetupCard()
            }

            if let record = practice.record(for: line, source: model.sourceName) {
                Divider()
                HistorySection(record: record)
            }

            HStack {
                Spacer()
                Button("Fechar") { dismiss() }
                    .buttonStyle(GlassButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 600)
        .background(AuroraBackground())
        .environment(\.colorScheme, .dark)
        .onDisappear(perform: cleanUp)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button("Ouvir o personagem", systemImage: "play.fill") { model.playSegment(line) }
                .buttonStyle(GlassButtonStyle())
                .disabled(recorder.isRecording || model.player == nil)

            if recorder.isRecording {
                Button("Parar", systemImage: "stop.fill") { recorder.stop() }
                    .buttonStyle(PrimaryButtonStyle(gradient: LinearGradient(colors: [.red, Theme.pink], startPoint: .leading, endPoint: .trailing)))
                    .keyboardShortcut(.defaultAction)
                LevelMeter(level: recorder.level)
                Text("Fale agora…").foregroundStyle(Theme.textDim)
            } else {
                Button(phase == .idle ? "Gravar" : "Gravar de novo", systemImage: "mic.fill") {
                    Task { await startRecording() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(phase == .analyzing)

                if recording != nil, phase != .analyzing {
                    Button("Ouvir minha voz", systemImage: "waveform") { playRecording() }
                        .buttonStyle(GlassButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            Text("Ouça o personagem, clique em **Gravar** e repita a frase. A gravação para sozinha quando você termina de falar.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .recording:
            EmptyView()
        case .analyzing:
            HStack {
                ProgressView().controlSize(.small)
                Text("Analisando a sua pronúncia…")
            }
        case .result(let result):
            ResultView(result: result)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func startRecording() async {
        guard await VoiceRecorder.requestPermission() else {
            phase = .failed("Permita o acesso ao microfone em Ajustes do Sistema › Privacidade e Segurança › Microfone.")
            return
        }
        model.stopSegment()
        model.pause()
        playback?.stop()
        deleteRecording()

        let url = AppFolders.practice.appendingPathComponent("\(UUID().uuidString).wav")
        let limit = max(8, (line.end - line.start) * 2.5 + 3)
        do {
            try recorder.start(to: url, maxDuration: limit) { url, _ in
                Task { await analyze(url) }
            }
            recording = url
            phase = .recording
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func analyze(_ url: URL) async {
        phase = .analyzing
        do {
            let result = try await model.assess(recording: url, line: line, phonemes: phonemes)
            practice.add(result, for: line, source: model.sourceName)
            phase = .result(result)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func playRecording() {
        guard let recording else { return }
        model.stopSegment()
        playback = try? AVAudioPlayer(contentsOf: recording)
        playback?.play()
    }

    private func deleteRecording() {
        guard let recording else { return }
        try? FileManager.default.removeItem(at: recording)
        try? FileManager.default.removeItem(at: recording.deletingPathExtension().appendingPathExtension("json"))
        self.recording = nil
    }

    private func cleanUp() {
        recorder.stop()
        playback?.stop()
        model.stopSegment()
        deleteRecording()
    }
}

private struct ResultView: View {
    let result: PronunciationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 24) {
                ScoreRing(score: result.score, size: 110)
                VStack(alignment: .leading, spacing: 8) {
                    Text(scoreLabel(result.score)).font(.system(size: 22, weight: .heavy))
                    Metric(title: "Precisão", value: result.accuracy)
                    Metric(title: "Fluência", value: result.fluency)
                    Metric(title: "Completude", value: result.completeness)
                    if let sounds = result.sounds {
                        Metric(title: "Sons", value: sounds.score)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()

            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Array(result.words.enumerated()), id: \.offset) { _, word in
                    Text(word.text)
                        .font(.title3.weight(.semibold))
                        .strikethrough(word.status == .missing)
                        .foregroundStyle(color(for: word.status))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(color(for: word.status).opacity(0.16)))
                        .overlay(Capsule().strokeBorder(color(for: word.status).opacity(0.35)))
                        .help(help(for: word))
                }
            }

            HStack(spacing: 14) {
                legend(.correct, "correta")
                legend(.unsure, "pouco clara")
                legend(.wrong, "errada")
                legend(.missing, "faltou")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !result.recognizedText.isEmpty {
                Text("Entendi: “\(result.recognizedText.trimmingCharacters(in: .whitespaces))”")
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(result.tips, id: \.self) { tip in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill").foregroundStyle(Theme.orange)
                        Text(tip).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.orange.opacity(0.1)))
                }
            }

            if let sounds = result.sounds {
                SoundsSection(sounds: sounds)
            }
        }
    }

    private func legend(_ status: PronunciationResult.WordStatus, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color(for: status)).frame(width: 8, height: 8)
            Text(title)
        }
    }

    private func help(for word: PronunciationResult.WordResult) -> String {
        switch word.status {
        case .correct: "Correta"
        case .unsure: word.heard.map { "Parecida: entendi “\($0)”" } ?? "Saiu pouco clara"
        case .wrong: "Entendi “\(word.heard ?? "?")”"
        case .missing: "Não foi dita"
        }
    }

    private func color(for status: PronunciationResult.WordStatus) -> Color {
        switch status {
        case .correct: .green
        case .unsure: .yellow
        case .wrong: .red
        case .missing: .gray
        }
    }
}

/// Sound-by-sound feedback: each word's expected sounds, colored by how they came out.
private struct SoundsSection: View {
    let sounds: SoundAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sons").font(.headline)
            let problems = sounds.words.filter { word in
                !word.extra.isEmpty || word.sounds.contains { $0.status != .correct }
            }
            if problems.isEmpty {
                Label("Todos os sons saíram corretos!", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(Array(problems.enumerated()), id: \.offset) { _, word in
                    HStack(alignment: .top, spacing: 10) {
                        Text(word.text)
                            .font(.callout.bold())
                            .frame(width: 90, alignment: .leading)
                        FlowLayout(spacing: 4, lineSpacing: 4) {
                            ForEach(Array(word.sounds.enumerated()), id: \.offset) { _, sound in
                                SoundChip(sound: sound)
                            }
                            ForEach(Array(word.extra.enumerated()), id: \.offset) { _, extra in
                                Text("+\(extra)")
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 5)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.purple.opacity(0.12)))
                                    .help("Som a mais: /\(extra)/")
                            }
                        }
                    }
                }
            }
            ForEach(sounds.tips, id: \.self) { tip in
                Label(tip, systemImage: "mouth")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SoundChip: View {
    let sound: SoundAnalysis.Sound

    var body: some View {
        VStack(spacing: 0) {
            Text(sound.expected)
                .font(.system(.callout, design: .monospaced))
                .strikethrough(sound.status == .missing)
            if let heard = sound.heard {
                Text(heard)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.13)))
        .help(help)
    }

    private var color: Color {
        switch sound.status {
        case .correct: .green
        case .close: .yellow
        case .wrong: .red
        case .missing: .gray
        }
    }

    private var help: String {
        let name = PhonemeTips.name(for: sound.expected).map { " — \($0)" } ?? ""
        switch sound.status {
        case .correct: return "/\(sound.expected)/\(name): correto"
        case .close: return "/\(sound.expected)/\(name): saiu parecido com /\(sound.heard ?? "?")/"
        case .wrong: return "/\(sound.expected)/\(name): você disse /\(sound.heard ?? "?")/"
        case .missing: return "/\(sound.expected)/\(name): não foi pronunciado"
        }
    }
}

/// Offers the one-time install of the sound analysis.
private struct SoundsSetupCard: View {
    @EnvironmentObject private var phonemes: PhonemeEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Análise por som", systemImage: "mouth").font(.headline)
            switch phonemes.state {
            case .notInstalled, .ready:
                Text("Descubra exatamente qual som saiu errado (o “th”, o R americano, “ship” × “sheep”…). Instalação única: baixa cerca de 1,5 GB e ocupa uns 450 MB depois.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Ativar análise por som") { phonemes.install() }
            case .installing(let progress, let message):
                ProgressView(value: progress) { Text(message) }
                Text("Pode continuar praticando enquanto isso.").font(.caption).foregroundStyle(.secondary)
            case .failed(let message):
                Text(message)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Button("Tentar de novo") { phonemes.install() }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}

private struct Metric: View {
    let title: String
    let value: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(title).foregroundStyle(Theme.textDim).frame(width: 84, alignment: .leading)
            GradientProgress(value: value).frame(width: 170)
            Text("\(Int((value * 100).rounded()))").fontWeight(.semibold).monospacedDigit().frame(width: 30, alignment: .trailing)
        }
        .font(.callout)
    }
}

private struct HistorySection: View {
    let record: PracticeRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Seu histórico nesta fala").font(.headline)
                Spacer()
                Text("Melhor nota: **\(record.best)** · \(record.attempts.count) tentativa\(record.attempts.count == 1 ? "" : "s")")
                    .font(.callout)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(record.attempts.suffix(12).reversed()) { attempt in
                        VStack(spacing: 2) {
                            Text("\(attempt.score)")
                                .font(.callout.bold())
                                .foregroundStyle(scoreColor(attempt.score))
                            Text(attempt.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(scoreColor(attempt.score).opacity(0.12)))
                    }
                }
            }
        }
    }
}

/// Circular score from 0 to 100.
struct ScoreRing: View {
    let score: Int
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: size * 0.1)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(
                    AngularGradient(colors: [scoreColor(score).opacity(0.6), scoreColor(score)], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360 * Double(score) / 100)),
                    style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: scoreColor(score).opacity(0.55), radius: size * 0.08)
            Text("\(score)").font(.system(size: size * 0.34, weight: .heavy)).monospacedDigit()
        }
        .frame(width: size, height: size)
        .padding(size * 0.05)
    }
}

func scoreColor(_ score: Int) -> Color {
    switch score {
    case 80...: Color(red: 0.204, green: 0.827, blue: 0.600)   // #34D399
    case 60..<80: Color(red: 0.984, green: 0.749, blue: 0.141) // #FBBF24
    default: Color(red: 0.973, green: 0.443, blue: 0.443)      // #F87171
    }
}

/// Live microphone level while recording.
private struct LevelMeter: View {
    let level: Double

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<16, id: \.self) { index in
                let threshold = Double(index) / 16
                Capsule()
                    .fill(level > threshold ? AnyShapeStyle(Theme.warm) : AnyShapeStyle(Color.white.opacity(0.12)))
                    .frame(width: 4, height: 6 + CGFloat(sin(Double(index) * 0.7) + 1) * 7)
            }
        }
        .animation(.easeOut(duration: 0.1), value: level)
    }
}

func scoreLabel(_ score: Int) -> String {
    switch score {
    case 90...: "Excelente!"
    case 75..<90: "Muito bom!"
    case 60..<75: "Bom"
    case 40..<60: "Continue praticando"
    default: "Tente de novo"
    }
}

func formatTime(_ seconds: Double) -> String {
    let total = Int(seconds)
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
