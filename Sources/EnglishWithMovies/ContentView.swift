import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @ViewState private var isDropTargeted = false

    var body: some View {
        Group {
            if model.mediaURL == nil {
                DropZone(isTargeted: isDropTargeted)
            } else {
                VSplitView {
                    PlayerArea()
                        .frame(minHeight: 180, idealHeight: 380)
                    VStack(spacing: 0) {
                        StatusBar()
                        TranscriptView()
                    }
                    .frame(minHeight: 200)
                }
            }
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
                Button("Importar legenda", systemImage: "captions.bubble") { FilePicker.openSubtitles(model) }
                Button("Abrir", systemImage: "folder") { FilePicker.openMedia(model) }
            }
        }
        .navigationTitle(model.mediaURL?.lastPathComponent ?? "English with Movies & Music")
    }
}

private struct DropZone: View {
    @EnvironmentObject private var model: AppModel
    let isTargeted: Bool

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
            Button("Escolher arquivo…") { FilePicker.openMedia(model) }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
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
                Button("Tentar de novo") { model.retranscribe() }
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
