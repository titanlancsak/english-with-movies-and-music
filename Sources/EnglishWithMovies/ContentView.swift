import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var savedWords: SavedWordsStore
    @Environment(\.openWindow) private var openWindow
    @ViewState private var isDropTargeted = false
    @ViewState private var showLinkSheet = false
    @ViewState private var cleanupSize: Int64?

    var body: some View {
        VStack(spacing: 0) {
            StatusBar()
            if model.mediaURL == nil {
                DropZone(isTargeted: isDropTargeted, showLinkSheet: $showLinkSheet)
            } else {
                VSplitView {
                    PlayerArea()
                        .frame(minHeight: 180, idealHeight: 380)
                    TranscriptView()
                        .frame(minHeight: 200)
                }
            }
        }
        .sheet(isPresented: $showLinkSheet) {
            LinkSheet { link in model.download(from: link) }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.open(url) }
            }
            return true
        }
        .toolbar {
            ToolbarItemGroup {
                Picker("Modelo", selection: $model.model) {
                    ForEach(WhisperModel.allCases) { Text($0.title).tag($0) }
                }
                .help("Modelo de transcrição: os maiores são mais precisos e mais lentos")
                Button("Transcrever de novo", systemImage: "arrow.clockwise") { model.retranscribe() }
                    .disabled(model.mediaURL == nil)
                Button("Baixar do YouTube", systemImage: "link") { showLinkSheet = true }
                    .help("Baixar um vídeo a partir de um link do YouTube")
                Button("Importar legenda", systemImage: "captions.bubble") { FilePicker.openSubtitles(model) }
                Button("Abrir", systemImage: "folder") { FilePicker.openMedia(model) }
                Button("Palavras salvas (\(savedWords.list.words.count))", systemImage: "bookmark") {
                    openWindow(id: "saved-words")
                }
                .help("Palavras salvas (⇧⌘S)")
                Button("Limpar cópias", systemImage: "trash") { cleanupSize = model.convertedCopiesSize() }
                    .help("Apagar as cópias convertidas para liberar espaço")
                    .disabled(model.isBusy)
            }
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
        .navigationTitle(model.mediaURL?.lastPathComponent ?? "English with Movies & Music")
    }

    private var cleanupTitle: String {
        guard let size = cleanupSize, size > 0 else { return "Não há cópias para apagar" }
        return "Apagar cópias convertidas (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))?"
    }
}

private struct DropZone: View {
    @EnvironmentObject private var model: AppModel
    let isTargeted: Bool
    @Binding var showLinkSheet: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "film.stack")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Arraste um filme ou uma música aqui")
                .font(.title2.bold())
            Text("O app transcreve as falas, mostra a legenda em tempo real\ne explica qualquer palavra em que você clicar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button("Escolher arquivo…") { FilePicker.openMedia(model) }
                    .buttonStyle(.borderedProminent)
                Button("Baixar do YouTube…") { showLinkSheet = true }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary.opacity(0.4))
                .padding(24)
        )
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
                    VStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .font(.system(size: 48))
                        Text(model.mediaURL?.deletingPathExtension().lastPathComponent ?? "")
                            .font(.title3)
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

private struct StatusBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.status {
        case .working(let message, let progress):
            HStack {
                if let progress {
                    ProgressView(value: progress) { Text(message) }
                } else {
                    ProgressView().controlSize(.small)
                    Text(message)
                }
                Button("Cancelar") { model.cancel() }
            }
            .padding(10)
            .background(.bar)
        case .failed(let message):
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).textSelection(.enabled)
                Spacer()
                if model.mediaURL != nil {
                    Button("Tentar de novo") { model.retranscribe() }
                }
            }
            .padding(10)
            .background(.bar)
        case .idle, .ready:
            EmptyView()
        }
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
            Text("Cole o link do vídeo. Ele é salvo em Filmes › English with Movies e transcrito em seguida.")
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
