import AppKit
import SwiftUI

/// Home screen: a greeting with the study numbers, the featured item and rows of covers.
struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var savedWords: SavedWordsStore
    @EnvironmentObject private var practice: PracticeStore
    @EnvironmentObject private var study: StudyStore
    @Binding var showLinkSheet: Bool
    @ViewState private var deleteCandidate: LibraryItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                header
                if let featured = library.featured {
                    Hero(item: featured, play: play)
                }
                row("Continuar assistindo", library.continueWatching)
                row("Baixados do YouTube", library.downloads)
                row("Filmes e vídeos", library.videos)
                row("Músicas", library.music)
            }
            .padding(.vertical, 24)
        }
        .scrollIndicators(.never)
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

    private var header: some View {
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.greeting)
                    .font(.system(size: 30, weight: .heavy))
                    .gradientForeground()
                Text("O que vamos assistir em inglês hoje?")
                    .foregroundStyle(Theme.textDim)
            }
            .fixedSize()
            Spacer(minLength: 20)
            GoalCard()
            StatCard(value: "\(savedWords.list.words.count)", title: "palavras salvas", icon: "bookmark.fill", tint: Theme.indigo) {
                model.section = .savedWords
            }
            StatCard(value: "\(savedWords.list.due().count)", title: "para revisar", icon: "rectangle.on.rectangle.angled.fill",
                     tint: Theme.orange, highlighted: !savedWords.list.due().isEmpty) {
                model.section = .review
            }
            StatCard(value: practice.history.averageScore.map(String.init) ?? "–", title: "média de pronúncia",
                     icon: "waveform", tint: Theme.violet) {
                model.section = .practice
            }
        }
        .padding(.horizontal, 28)
    }

    private static var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Bom dia!"
        case 12..<18: "Boa tarde!"
        default: "Boa noite!"
        }
    }

    @ViewBuilder
    private func row(_ title: String, _ items: [LibraryItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: 19, weight: .bold))
                    Text("\(items.count)").font(.callout.weight(.semibold)).foregroundStyle(Theme.textDim)
                }
                .padding(.horizontal, 28)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(items) { item in
                            Card(item: item, play: play, remove: remove)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                }
            }
        }
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

/// The daily goal: days in a row and today's progress; clicking changes the goal.
private struct GoalCard: View {
    @EnvironmentObject private var study: StudyStore

    var body: some View {
        let progress = study.log.todayProgress()
        let streak = study.log.streak()
        Menu {
            Section("Meta diária") {
                ForEach([5, 10, 15, 20, 30, 45, 60], id: \.self) { minutes in
                    Button { study.goalMinutes = minutes } label: {
                        if minutes == study.goalMinutes {
                            Label("\(minutes) min por dia", systemImage: "checkmark")
                        } else {
                            Text("\(minutes) min por dia")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Theme.warm, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(streak > 0 ? Theme.orange : Theme.textDim)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 0) {
                    Text(streak == 1 ? "1 dia" : "\(streak) dias").font(.system(size: 18, weight: .heavy).monospacedDigit())
                    Text("hoje: \(min(study.todayMinutes, 999))/\(study.goalMinutes) min")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(progress >= 1 ? Theme.orange : Theme.textDim)
                }
                .fixedSize()
            }
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .padding(.vertical, 9)
            .glassCard(cornerRadius: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.orange.opacity(progress >= 1 ? 0.6 : 0), lineWidth: 1)
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sequência de dias em que você atingiu a meta. Assistir, revisar e praticar contam. Clique para mudar a meta.")
    }
}

/// A number with a label, e.g. "12 palavras salvas"; clicking opens that screen.
private struct StatCard: View {
    let value: String
    let title: String
    let icon: String
    let tint: Color
    var highlighted = false
    let action: () -> Void
    @ViewState private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.gradient))
                VStack(alignment: .leading, spacing: 0) {
                    Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit())
                    Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textDim)
                }
                .fixedSize()
            }
            .padding(.leading, 10)
            .padding(.trailing, 16)
            .padding(.vertical, 9)
            .glassCard(cornerRadius: 14, highlighted: isHovered)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tint.opacity(highlighted ? 0.6 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
                .frame(height: 360)
                .frame(maxWidth: .infinity)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.8), .black.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing)

            VStack(alignment: .leading, spacing: 12) {
                Chip(text: item.lastOpened == nil ? "NOVO NA BIBLIOTECA" : "ASSISTIDO RECENTEMENTE",
                     systemImage: item.lastOpened == nil ? "sparkles" : "clock.fill", color: Theme.orange)
                Text(item.title)
                    .font(.system(size: 36, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: 620, alignment: .leading)
                    .shadow(color: .black.opacity(0.4), radius: 8)
                HStack(spacing: 8) {
                    ItemDetails(item: item)
                    if item.hasTranscript { Chip(text: "Legendas prontas", systemImage: "captions.bubble.fill", color: .white) }
                }
                if item.isInProgress, let progress = item.progress {
                    GradientProgress(value: progress, height: 5).frame(width: 300)
                }
                HStack(spacing: 10) {
                    Button { play(item, false) } label: {
                        Label(item.isInProgress ? "Continuar" : "Assistir", systemImage: "play.fill")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    if item.isInProgress {
                        Button { play(item, true) } label: {
                            Label("Do início", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                }
                .padding(.top, 4)
            }
            .padding(32)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
        .padding(.horizontal, 28)
    }
}

// MARK: - Cards

private struct Card: View {
    let item: LibraryItem
    let play: (LibraryItem, Bool) -> Void
    let remove: (LibraryItem) -> Void
    @ViewState private var isHovered = false

    private static let width: CGFloat = 248

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottom) {
                Cover(item: item, showTitle: true)
                    .frame(width: Self.width, height: Self.width * 9 / 16)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if item.isInProgress, let progress = item.progress {
                    GradientProgress(value: progress, height: 4)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isHovered ? AnyShapeStyle(Theme.warm) : AnyShapeStyle(Theme.stroke), lineWidth: isHovered ? 2 : 1)
            )
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
                    }
                    .buttonStyle(IconButtonStyle(size: 26))
                    .help(item.isDownload ? "Apagar o vídeo baixado" : "Remover da biblioteca (o arquivo continua no seu Mac)")
                    .padding(8)
                }
            }
            .overlay {
                if isHovered {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Theme.brand))
                        .shadow(color: Theme.violet.opacity(0.6), radius: 12)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: isHovered ? Theme.violet.opacity(0.35) : .black.opacity(0.35), radius: isHovered ? 18 : 8, y: 6)
            .offset(y: isHovered ? -4 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                ItemDetails(item: item).font(.caption)
            }
            .frame(width: Self.width, alignment: .leading)
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
        .foregroundStyle(.white.opacity(0.6))
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
