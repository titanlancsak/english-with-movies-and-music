import AVFoundation
import LinguaCore
import SwiftUI

/// Sheet for practicing one subtitle line: listen, record, get a score.
struct PracticeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var practice: PracticeStore
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
            HStack(alignment: .firstTextBaseline) {
                Text("Pratique a fala").font(.title2.bold())
                Spacer()
                if let source = model.sourceName {
                    Text("\(source) · \(formatTime(line.start))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(line.text)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.1)))
                .textSelection(.enabled)

            controls
            content

            if let record = practice.record(for: line, source: model.sourceName) {
                Divider()
                HistorySection(record: record)
            }

            HStack {
                Spacer()
                Button("Fechar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onDisappear(perform: cleanUp)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button("Ouvir o personagem", systemImage: "play.circle") { model.playSegment(line) }
                .disabled(recorder.isRecording || model.player == nil)

            if recorder.isRecording {
                Button("Parar", systemImage: "stop.circle.fill") { recorder.stop() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
                ProgressView(value: recorder.level)
                    .frame(width: 120)
                    .tint(.red)
                Text("Fale agora…").foregroundStyle(.secondary)
            } else {
                Button(phase == .idle ? "Gravar" : "Gravar de novo", systemImage: "mic.circle.fill") {
                    Task { await startRecording() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(phase == .analyzing)

                if recording != nil, phase != .analyzing {
                    Button("Ouvir minha voz", systemImage: "waveform") { playRecording() }
                }
            }
        }
        .controlSize(.large)
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
            let result = try await model.assess(recording: url, line: line)
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
            HStack(spacing: 20) {
                ScoreRing(score: result.score, size: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text(scoreLabel(result.score)).font(.title3.bold())
                    Metric(title: "Precisão", value: result.accuracy)
                    Metric(title: "Fluência", value: result.fluency)
                    Metric(title: "Completude", value: result.completeness)
                }
            }

            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(Array(result.words.enumerated()), id: \.offset) { _, word in
                    Text(word.text)
                        .font(.title3.weight(.semibold))
                        .strikethrough(word.status == .missing)
                        .foregroundStyle(color(for: word.status))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(color(for: word.status).opacity(0.15)))
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
                    Label(tip, systemImage: "lightbulb")
                        .fixedSize(horizontal: false, vertical: true)
                }
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

private struct Metric: View {
    let title: String
    let value: Double

    var body: some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            ProgressView(value: value).frame(width: 160)
            Text("\(Int((value * 100).rounded()))").monospacedDigit().frame(width: 32, alignment: .trailing)
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
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: size * 0.1)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(scoreColor(score), style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(score)").font(.system(size: size * 0.34, weight: .bold)).monospacedDigit()
        }
        .frame(width: size, height: size)
        .padding(size * 0.05)
    }
}

func scoreColor(_ score: Int) -> Color {
    switch score {
    case 80...: .green
    case 60..<80: .orange
    default: .red
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
