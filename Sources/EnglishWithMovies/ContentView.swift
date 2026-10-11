import LinguaCore
import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var savedWords: SavedWordsStore
    @EnvironmentObject private var translator: Translator
    @EnvironmentObject private var practice: PracticeStore
    @EnvironmentObject private var phonemes: PhonemeEngine
    @EnvironmentObject private var library: LibraryStore
    @ViewState private var isDropTargeted = false
    @ViewState private var showLinkSheet = false
    @ViewState private var cleanupSize: Int64?
    /// Preview only: a word whose dictionary card is shown (`--word=`).
    @ViewState private var previewWord: PreviewWord?

    var body: some View {
        NavigationSplitView {
            Sidebar(showLinkSheet: $showLinkSheet, cleanupSize: $cleanupSize)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            ZStack {
                AuroraBackground()
                VStack(spacing: 0) {
                    StatusBar()
                    detail
                }
            }
            .toolbar { toolbar }
        }
        .sheet(isPresented: $showLinkSheet) {
            LinkSheet { link in model.download(from: link) }
        }
        .sheet(item: $previewWord) { preview in
            WordPopover(word: preview.word, line: preview.line)
                .environmentObject(model)
                .environmentObject(savedWords)
                .environmentObject(translator)
        }
        .sheet(item: $model.practiceLine) { line in
            PracticeView(line: line)
                .environmentObject(model)
                .environmentObject(practice)
                .environmentObject(phonemes)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.open(url) }
            }
            return true
        }
        // Leaving the player pauses it; the film stays open under "Assistindo".
        .onChange(of: model.section) { _, section in
            if section != .player { model.pause() }
        }
        .confirmationDialog(
            cleanupTitle,
            isPresented: Binding(get: { cleanupSize != nil }, set: { if !$0 { cleanupSize = nil } })
        ) {
            if cleanupSize ?? 0 > 0 {
                Button("Apagar", role: .destructive) { model.clearConvertedCopies() }
            } else {
                Button("OK") {}
            }
        } message: {
            Text(cleanupSize ?? 0 > 0
                ? "Os arquivos originais e as transcrições são mantidos. Se você abrir o vídeo de novo, o app converte outra vez."
                : "As cópias convertidas aparecem aqui quando o app converte vídeos .mkv, VP9 ou AV1.")
        }
        .onAppear(perform: applyPreviewArguments)
        .navigationTitle(title)
        .tint(Theme.violet)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.section {
        case .player where model.mediaURL != nil:
            PlayerScreen()
        case .savedWords:
            SavedWordsView()
        case .review:
            ReviewView()
        case .practice:
            PracticeHistoryView()
        default:
            if library.items.isEmpty {
                DropZone(isTargeted: isDropTargeted, showLinkSheet: $showLinkSheet)
            } else {
                LibraryView(showLinkSheet: $showLinkSheet)
            }
        }
    }

    /// Used for screenshots, with `--preview`:
    /// `--section=words|review|practice` opens a screen; with a film open, `--practice` opens the
    /// practice sheet for the current line and `--word=harbor` shows that word's dictionary card.
    private func applyPreviewArguments() {
        guard AppModel.isPreview else { return }
        let arguments = CommandLine.arguments
        switch arguments.first(where: { $0.hasPrefix("--section=") })?.dropFirst(10) {
        case "words": model.section = .savedWords
        case "review": model.section = .review
        case "practice": model.section = .practice
        default: break
        }
        let word = arguments.first { $0.hasPrefix("--word=") }.map { String($0.dropFirst(7)) }
        guard word != nil || arguments.contains("--practice") else { return }
        Task {
            for _ in 0..<40 where model.transcript == nil { try? await Task.sleep(for: .milliseconds(250)) }
            try? await Task.sleep(for: .milliseconds(500))
            guard let transcript = model.transcript, !transcript.lines.isEmpty else { return }
            let line = transcript.lines[model.activeLine ?? 0]
            if let word {
                previewWord = PreviewWord(word: word, line: line)
            } else {
                model.practiceLine = line
            }
        }
    }

    private var title: String {
        switch model.section {
        case .player: model.sourceName ?? "Assistindo"
        case .savedWords: "Palavras salvas"
        case .review: "Revisão"
        case .practice: "Pronúncia"
        case .library: "Biblioteca"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if model.section == .player, model.mediaURL != nil {
            ToolbarItemGroup {
                Toggle("Tradução", systemImage: "character.bubble", isOn: $translator.showLineTranslations)
                    .help("Mostrar a tradução em português embaixo de cada fala")
                    .disabled(!translator.isSupportedOS)
                Button("Importar legenda", systemImage: "captions.bubble") { FilePicker.openSubtitles(model) }
                    .help("Usar uma legenda .srt em vez da transcrição")
                Button("Transcrever de novo", systemImage: "arrow.clockwise") { model.retranscribe() }
                Button("Fechar", systemImage: "xmark") { model.closeMedia() }
                    .help("Fechar e voltar para a biblioteca")
            }
        } else if model.section == .library {
            ToolbarItemGroup {
                Button("Baixar do YouTube", systemImage: "link") { showLinkSheet = true }
                    .help("Baixar um vídeo a partir de um link do YouTube")
                Button("Abrir", systemImage: "plus") { FilePicker.openMedia(model) }
                    .help("Abrir um filme ou uma música (⌘O)")
            }
        }
    }

    private var cleanupTitle: String {
        guard let size = cleanupSize, size > 0 else { return "Não há cópias para apagar" }
        return "Apagar cópias convertidas (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))?"
    }
}

/// Navigation on the left: library, the open film, saved words, review and pronunciation.
private struct Sidebar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var savedWords: SavedWordsStore
    @EnvironmentObject private var practice: PracticeStore
    @Binding var showLinkSheet: Bool
    @Binding var cleanupSize: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if let icon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable().frame(width: 34, height: 34)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("English").font(.system(size: 15, weight: .heavy))
                    Text("with Movies & Music").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textDim)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 18)

            SectionLabel(text: "Assistir").padding(.horizontal, 10).padding(.bottom, 2)
            item(.library, "Biblioteca", "square.grid.2x2.fill")
            if let name = model.sourceName {
                item(.player, name, model.hasVideo ? "play.rectangle.fill" : "music.note", subtitle: "Assistindo agora")
            }

            SectionLabel(text: "Aprender").padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 2)
            item(.savedWords, "Palavras salvas", "bookmark.fill", badge: savedWords.list.words.count, badgeColor: Theme.textDim)
            item(.review, "Revisão", "rectangle.on.rectangle.angled.fill", badge: savedWords.list.due().count, badgeColor: Theme.orange)
            item(.practice, "Pronúncia", "waveform", badge: practice.history.averageScore, badgeColor: Theme.textDim)

            Spacer()

            transcriptionCard
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func item(_ section: AppModel.Section, _ title: String, _ icon: String, subtitle: String? = nil,
                      badge: Int? = nil, badgeColor: Color = .white) -> some View {
        SidebarItem(title: title, subtitle: subtitle, icon: icon, badge: badge.flatMap { $0 > 0 ? "\($0)" : nil },
                    badgeColor: badgeColor, isSelected: model.section == section) {
            model.section = section
        }
    }

    /// Which Whisper model transcribes, plus housekeeping.
    private var transcriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Transcrição")
            Picker("Modelo", selection: $model.model) {
                ForEach(WhisperModel.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .help("Modelo de transcrição: os maiores são mais precisos e mais lentos")
            Button("Liberar espaço…") { cleanupSize = model.convertedCopiesSize() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Theme.textDim)
                .help("Apagar as cópias convertidas de vídeos .mkv, VP9 e AV1")
                .disabled(model.isBusy)
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }
}

private struct SidebarItem: View {
    let title: String
    var subtitle: String?
    let icon: String
    var badge: String?
    var badgeColor: Color = .white
    let isSelected: Bool
    let action: () -> Void
    @ViewState private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(isSelected ? .white : Theme.textDim)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Theme.surface))
                    )
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.orange)
                    }
                }
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(badgeColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.1) : isHovered ? Color.white.opacity(0.05) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct DropZone: View {
    @EnvironmentObject private var model: AppModel
    let isTargeted: Bool
    @Binding var showLinkSheet: Bool

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.brand).frame(width: 96, height: 96).blur(radius: 30).opacity(0.7)
                Image(systemName: "film.stack.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text("Aprenda inglês com o que você ama assistir")
                .font(.system(size: 30, weight: .heavy))
                .multilineTextAlignment(.center)
                .gradientForeground()
            Text("Arraste um filme ou uma música para cá. O app transcreve as falas, mostra a legenda\nem tempo real e explica qualquer palavra em que você clicar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textDim)
            HStack(spacing: 12) {
                Button("Escolher arquivo…", systemImage: "folder.fill") { FilePicker.openMedia(model) }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Baixar do YouTube…", systemImage: "link") { showLinkSheet = true }
                    .buttonStyle(GlassButtonStyle())
            }
            .padding(.top, 6)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                .foregroundStyle(isTargeted ? Theme.violet : Color.white.opacity(0.15))
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(isTargeted ? Theme.violet.opacity(0.08) : .clear)
                )
                .padding(28)
        )
        .animation(.easeOut(duration: 0.2), value: isTargeted)
    }
}

/// The open film or song: the video on top and the interactive subtitles below.
private struct PlayerScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GeometryReader { geometry in
            let videoHeight = min(geometry.size.width * 9 / 16, geometry.size.height * 0.56)
            VStack(spacing: 14) {
                PlayerArea()
                    .frame(maxWidth: videoHeight * 16 / 9, maxHeight: videoHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1)
                    )
                    .shadow(color: Theme.indigo.opacity(0.35), radius: 40, y: 10)
                    .frame(maxWidth: .infinity)
                TranscriptView()
                    .glassCard(cornerRadius: 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }
}

private struct PlayerArea: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color.black
            if let player = model.player {
                PlayerView(player: player)
                if !model.hasVideo {
                    ZStack {
                        LinearGradient(colors: [Theme.indigo.opacity(0.6), Theme.violet.opacity(0.5), Theme.orange.opacity(0.35)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        VStack(spacing: 10) {
                            Image(systemName: "music.note")
                                .font(.system(size: 52, weight: .semibold))
                            Text(model.sourceName ?? "")
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .foregroundStyle(.white)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

private struct StatusBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.status {
            case .working(let message, let progress):
                HStack(spacing: 14) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(message).font(.callout.weight(.medium))
                            Spacer()
                            if let progress {
                                Text("\(Int(progress * 100))%").font(.callout.monospacedDigit()).foregroundStyle(Theme.textDim)
                            }
                        }
                        if let progress {
                            GradientProgress(value: progress)
                        }
                    }
                    Button("Cancelar") { model.cancel() }.buttonStyle(GlassButtonStyle())
                }
                .padding(14)
                .glassCard(cornerRadius: 14)
            case .failed(let message):
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.orange)
                    Text(message).textSelection(.enabled).font(.callout)
                    Spacer()
                    if model.mediaURL != nil {
                        Button("Tentar de novo") { model.retranscribe() }.buttonStyle(GlassButtonStyle())
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.orange.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.orange.opacity(0.3)))
            case .idle, .ready:
                EmptyView()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

/// A thin progress bar filled with the brand gradient.
struct GradientProgress: View {
    let value: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(Theme.warm).frame(width: max(height, geometry.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

/// The native macOS player (AVPlayerView). SwiftUI's VideoPlayer crashes on some SDK/OS combinations.
private struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

/// Asks for a video link (YouTube or any site supported by yt-dlp).
private struct LinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState private var link = ""
    let onDownload: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Baixar do YouTube").font(.title3.bold())
            Text("Cole o link do vídeo. Ele é baixado, transcrito e fica salvo na sua biblioteca (Filmes › English with Movies).")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("https://www.youtube.com/watch?v=…", text: $link)
                .textFieldStyle(.roundedBorder)
                .onSubmit(download)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Baixar", action: download)
                    .keyboardShortcut(.defaultAction)
                    .disabled(URL(string: link.trimmingCharacters(in: .whitespaces))?.host == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            // Pre-fill with a link from the clipboard, if there is one.
            if let copied = NSPasteboard.general.string(forType: .string), copied.hasPrefix("http") {
                link = copied
            }
        }
    }

    private func download() {
        guard URL(string: link.trimmingCharacters(in: .whitespaces))?.host != nil else { return }
        onDownload(link)
        dismiss()
    }
}

private struct PreviewWord: Identifiable {
    let word: String
    let line: TranscriptLine
    var id: String { word }
}
