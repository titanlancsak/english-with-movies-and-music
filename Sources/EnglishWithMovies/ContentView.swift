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
                    UpdateBanner()
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
    /// `--section=words|review|practice` opens a screen; `--settings` the settings; with a film open,
    /// `--practice` opens the practice sheet for the current line, `--word=harbor` that word's
    /// dictionary card, `--search=text` the search and `--challenge` the listening challenge.
    private func applyPreviewArguments() {
        guard AppModel.isPreview else { return }
        let arguments = CommandLine.arguments
        switch arguments.first(where: { $0.hasPrefix("--section=") })?.dropFirst(10) {
        case "words": model.section = .savedWords
        case "review": model.section = .review
        case "practice": model.section = .practice
        default: break
        }
        if arguments.contains("--challenge") { model.hideSubtitles = true }
        let word = arguments.first { $0.hasPrefix("--word=") }.map { String($0.dropFirst(7)) }
        if let search = arguments.first(where: { $0.hasPrefix("--search=") })?.dropFirst(9) {
            model.showSearch = true
            Task {
                for _ in 0..<40 where model.transcript == nil { try? await Task.sleep(for: .milliseconds(250)) }
                model.searchQuery = String(search)
            }
        }
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
    @EnvironmentObject private var study: StudyStore
    @EnvironmentObject private var sync: SyncService
    @EnvironmentObject private var updates: UpdateChecker
    @Binding var showLinkSheet: Bool
    @Binding var cleanupSize: Int64?
    @ViewState private var showSettings = AppModel.isPreview && CommandLine.arguments.contains("--settings")

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

    /// Settings, with the transcription model and the sync state at a glance.
    private var transcriptionCard: some View {
        Button { showSettings = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(Theme.textDim)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ajustes").font(.system(size: 13, weight: .semibold))
                    Text(sync.folder == nil ? model.model.title : "Sincronização ligada")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .glassCard(cornerRadius: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(model)
                .environmentObject(study)
                .environmentObject(sync)
                .environmentObject(updates)
        }
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
            let videoHeight = min(geometry.size.width * 9 / 16, geometry.size.height * 0.5)
            VStack(spacing: 14) {
                PlayerArea()
                    .frame(maxWidth: videoHeight * 16 / 9, maxHeight: videoHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1)
                    )
                    .shadow(color: Theme.indigo.opacity(0.35), radius: 40, y: 10)
                    .frame(maxWidth: .infinity)
                StudyBar()
                TranscriptView()
                    .glassCard(cornerRadius: 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }
}

/// Study tools under the video: repeat the line, speed, shadowing, listening challenge,
/// uncommon words and search.
private struct StudyBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            ToggleChip(title: "Repetir fala", icon: "repeat", isOn: model.loopLine, help: "Repete a fala atual sem parar (⌘L)") {
                model.loopLine.toggle()
            }
            SpeedPicker(speed: $model.speed)
            ToggleChip(title: "Shadowing", icon: "person.wave.2.fill", isOn: model.shadowing,
                       help: "Ouve uma fala, você repete, recebe a nota e segue para a próxima (⌥⌘R)") {
                model.startShadowing()
            }
            .disabled(model.transcript == nil)
            ToggleChip(title: "Desafio de escuta", icon: model.hideSubtitles ? "eye.slash.fill" : "eye.slash", isOn: model.hideSubtitles,
                       help: "Esconde a legenda: tente entender só ouvindo e clique na fala para conferir (⇧⌘E)") {
                model.hideSubtitles.toggle()
            }
            ToggleChip(title: "Palavras difíceis", icon: "sparkles", isOn: model.highlightUncommon,
                       help: "Sublinha as palavras fora das 5.000 mais comuns do inglês") {
                model.highlightUncommon.toggle()
            }
            Spacer(minLength: 0)
            Button { model.showSearch.toggle() } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(IconButtonStyle(size: 30, tint: model.showSearch ? Theme.violet : .white))
                .help("Buscar na legenda (⌘F)")
                .disabled(model.transcript == nil)
        }
        .padding(.horizontal, 2)
    }
}

/// A capsule that lights up with the brand gradient when on.
struct ToggleChip: View {
    let title: String
    let icon: String
    let isOn: Bool
    var help = ""
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @ViewState private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .foregroundStyle(isOn ? .white : .white.opacity(isEnabled ? 0.8 : 0.35))
                .background(Capsule().fill(isOn ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(isHovered ? Theme.surfaceHover : Theme.surface)))
                .overlay(Capsule().strokeBorder(isOn ? Color.clear : Theme.stroke))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}

/// 0.5× 0.75× 1× 1.25×
private struct SpeedPicker: View {
    @Binding var speed: Float
    private static let options: [Float] = [0.5, 0.75, 1, 1.25]

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textDim)
                .padding(.leading, 8)
            ForEach(Self.options, id: \.self) { option in
                Button { speed = option } label: {
                    Text(option == 1 ? "1×" : String(format: "%g×", option).replacingOccurrences(of: ".", with: ","))
                        .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .foregroundStyle(speed == option ? .white : Theme.textDim)
                        .background(Capsule().fill(speed == option ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.clear)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().strokeBorder(Theme.stroke))
        .help("Velocidade (⌘[ e ⌘])")
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

/// "Nova versão disponível" when GitHub has a newer release.
private struct UpdateBanner: View {
    @EnvironmentObject private var updates: UpdateChecker

    var body: some View {
        if let available = updates.available {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").foregroundStyle(Theme.violet)
                Text("Nova versão \(available.version) disponível").font(.callout.weight(.semibold))
                Spacer()
                Button("Depois") { updates.dismiss() }.buttonStyle(GlassButtonStyle())
                Button("Baixar", systemImage: "arrow.down.circle.fill") { updates.download() }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(12)
            .glassCard(cornerRadius: 14)
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
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
