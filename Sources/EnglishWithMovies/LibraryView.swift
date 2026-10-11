import AppKit
import SwiftUI

/// Home screen: featured item and rows of covers, Netflix style.
struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var savedWords: SavedWordsStore
    @Environment(\.openWindow) private var openWindow
    @Binding var showLinkSheet: Bool
    @ViewState private var deleteCandidate: LibraryItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if let featured = library.featured {
                    Hero(item: featured, play: play)
                }
                row("Continuar assistindo", library.continueWatching)
                row("Baixados do YouTube", library.downloads)
                row("Filmes e vídeos", library.videos)
                row("Músicas", library.music)
                footer
            }
            .padding(.bottom, 30)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
        .environment(\.colorScheme, .dark)
        .onAppear { library.refresh() }
        .confirmationDialog(
            "Apagar “\(deleteCandidate?.title ?? "")”?",
            isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
        ) {
            Button("Apagar", role: .destructive) {
                if let item = deleteCandidate { library.delete(item) }
            }
        } message: {
            Text("O vídeo (\(ByteCountFormatter.string(fromByteCount: deleteCandidate?.size ?? 0, countStyle: .file))), a cópia convertida e a transcrição serão apagados. As palavras salvas e o histórico de pronúncia continuam.")
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ items: [LibraryItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(items) { item in
                            Card(item: item, play: play, remove: remove)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Abrir arquivo…", systemImage: "folder") { FilePicker.openMedia(model) }
            Button("Baixar do YouTube…", systemImage: "link") { showLinkSheet = true }
            let due = savedWords.list.due().count
            if due > 0 {
                Button("Revisar palavras (\(due))", systemImage: "rectangle.on.rectangle.angled") {
                    openWindow(id: "review")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            Spacer()
            if library.downloadsSize > 0 {
                Text("Downloads: \(ByteCountFormatter.string(fromByteCount: library.downloadsSize, countStyle: .file))")
                    .foregroundStyle(.secondary)
                Button("Mostrar pasta") { NSWorkspace.shared.open(AppFolders.downloads) }
            }
        }
        .padding(.horizontal, 32)
    }

    /// Resumes where playback stopped, unless the item was (almost) finished.
    private func play(_ item: LibraryItem, fromStart: Bool = false) {
        model.open(item.url, at: !fromStart && item.isInProgress ? item.position : nil)
    }

    private func remove(_ item: LibraryItem) {
        if item.isDownload {
            deleteCandidate = item
        } else {
            library.forget(item)
        }
    }
}

// MARK: - Featured

private struct Hero: View {
    @EnvironmentObject private var library: LibraryStore
    let item: LibraryItem
    let play: (LibraryItem, Bool) -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Cover(item: item, showTitle: false)
                .frame(height: 380)
                .frame(maxWidth: .infinity)
                .clipped()
            LinearGradient(colors: [.clear, Color(red: 0.08, green: 0.08, blue: 0.1)], startPoint: .center, endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .leading, endPoint: .center)

            VStack(alignment: .leading, spacing: 10) {
                Text(item.lastOpened == nil ? "NOVO NA BIBLIOTECA" : "ASSISTIDO RECENTEMENTE")
                    .font(.caption.bold())
                    .tracking(2)
                    .foregroundStyle(.orange)
                Text(item.title)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: 560, alignment: .leading)
                ItemDetails(item: item)
                if item.isInProgress, let progress = item.progress {
                    ProgressView(value: progress)
                        .tint(.orange)
                        .frame(width: 260)
                }
                HStack(spacing: 10) {
                    Button { play(item, false) } label: {
                        Label(item.isInProgress ? "Continuar" : "Assistir", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    if item.isInProgress {
                        Button { play(item, true) } label: {
                            Label("Do início", systemImage: "arrow.counterclockwise")
                                .font(.headline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.25)))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            .padding(32)
        }
    }
}

// MARK: - Cards

private struct Card: View {
    let item: LibraryItem
    let play: (LibraryItem, Bool) -> Void
    let remove: (LibraryItem) -> Void
    @ViewState private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                Cover(item: item, showTitle: true)
                    .frame(width: 256, height: 144)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                if item.isInProgress, let progress = item.progress {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.3))
                            Rectangle().fill(Color.orange).frame(width: geometry.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    if item.hasTranscript { Badge(text: "CC", help: "Legendas prontas") }
                    if item.isAudio { Badge(text: "♪", help: "Música") }
                }
                .padding(8)
            }
            .overlay(alignment: .topLeading) {
                if isHovered {
                    Button { remove(item) } label: {
                        Image(systemName: item.isDownload ? "trash" : "xmark")
                            .font(.caption.bold())
                            .padding(7)
                            .background(Circle().fill(.black.opacity(0.7)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .help(item.isDownload ? "Apagar o vídeo baixado" : "Remover da biblioteca (o arquivo continua no seu Mac)")
                    .padding(8)
                }
            }
            .overlay {
                if isHovered {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 6)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(isHovered ? 0.6 : 0.3), radius: isHovered ? 14 : 6, y: 4)
            .scaleEffect(isHovered ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: isHovered)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                ItemDetails(item: item).font(.caption)
            }
            .frame(width: 256, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { play(item, false) }
        .contextMenu {
            Button(item.isInProgress ? "Continuar" : "Assistir") { play(item, false) }
            if item.isInProgress {
                Button("Assistir do início") { play(item, true) }
            }
            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Divider()
            if item.isDownload {
                Button("Apagar vídeo…", role: .destructive) { remove(item) }
            } else {
                Button("Remover da biblioteca") { remove(item) }
            }
        }
    }
}

private struct Badge: View {
    let text: String
    let help: String

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.65)))
            .foregroundStyle(.white)
            .help(help)
    }
}

/// "1h 37min · 1,2 GB" plus how much is left when partially watched.
private struct ItemDetails: View {
    let item: LibraryItem

    var body: some View {
        HStack(spacing: 6) {
            if let duration = item.duration {
                Text(Self.format(duration))
            }
            if item.isInProgress, let duration = item.duration, let position = item.position {
                Text("· faltam \(Self.format(duration - position))")
            }
            Text("· \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))")
        }
        .foregroundStyle(.white.opacity(0.65))
    }

    static func format(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)min" }
        return minutes > 0 ? "\(minutes) min" : "\(Int(seconds)) s"
    }
}

/// The item's cover, or a colored placeholder when there is no image.
private struct Cover: View {
    @EnvironmentObject private var library: LibraryStore
    let item: LibraryItem
    let showTitle: Bool

    var body: some View {
        if let image = library.thumbnails[item.id] {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(colors: Self.colors(for: item.title), startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 8) {
                    Image(systemName: item.isAudio ? "music.note" : "film")
                        .font(.system(size: 30))
                    if showTitle {
                        Text(item.title)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 12)
                    }
                }
                .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    /// Stable colors per title, so each placeholder looks different.
    private static func colors(for title: String) -> [Color] {
        // hashValue changes on every launch, so use a fixed sum of the characters.
        let hue = Double(title.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 360 }) / 360
        return [Color(hue: hue, saturation: 0.6, brightness: 0.55), Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.3)]
    }
}
