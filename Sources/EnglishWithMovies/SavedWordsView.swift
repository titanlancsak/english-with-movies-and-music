import LinguaCore
import SwiftUI
import UniformTypeIdentifiers

/// The saved words, as cards with search, review and export.
struct SavedWordsView: View {
    @EnvironmentObject private var store: SavedWordsStore
    @EnvironmentObject private var model: AppModel
    @ViewState private var query = ""
    @ViewState private var exportError: String?

    var body: some View {
        let words = store.list.filtered(by: query)
        VStack(alignment: .leading, spacing: 18) {
            header
            if store.list.words.isEmpty {
                EmptyState(icon: "bookmark.fill", title: "Nenhuma palavra salva ainda",
                           text: "Clique numa palavra da legenda e toque em 🔖 para guardá-la aqui.")
            } else if words.isEmpty {
                EmptyState(icon: "magnifyingglass", title: "Nada encontrado", text: "Nenhuma palavra combina com “\(query)”.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                        ForEach(words) { word in
                            SavedWordRow(word: word)
                                .contextMenu {
                                    Button("Remover", role: .destructive) { store.remove(word.key) }
                                }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.top, 24)
        .alert("Não foi possível exportar", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Palavras salvas")
                        .font(.system(size: 30, weight: .heavy))
                        .gradientForeground()
                    Text("\(store.list.words.count) palavra\(store.list.words.count == 1 ? "" : "s") · \(store.list.masteredCount()) dominada\(store.list.masteredCount() == 1 ? "" : "s")")
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
                Button("Exportar CSV", systemImage: "square.and.arrow.up", action: export)
                    .buttonStyle(GlassButtonStyle())
                    .help("Exportar para planilha ou Anki")
                    .disabled(store.list.words.isEmpty)
                Button("Revisar (\(store.list.due().count))", systemImage: "rectangle.on.rectangle.angled.fill") {
                    model.section = .review
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(store.list.words.isEmpty)
            }
            SearchField(text: $query, prompt: "Buscar palavra, tradução, significado ou frase")
        }
        .padding(.horizontal, 28)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "palavras-salvas.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportCSV(to: url)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct SavedWordRow: View {
    @EnvironmentObject private var store: SavedWordsStore
    @EnvironmentObject private var model: AppModel
    let word: SavedWord
    @ViewState private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(word.word).font(.system(size: 22, weight: .heavy))
                        if let phonetic = word.phonetic {
                            Text(phonetic).font(.callout).foregroundStyle(Theme.textDim)
                        }
                    }
                    if let translation = word.translation {
                        Text(translation).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.orange)
                    }
                }
                Spacer()
                ReviewStatus(review: word.review)
            }

            if let definition = word.definition {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let partOfSpeech = word.partOfSpeech {
                        Chip(text: partOfSpeech, color: Theme.violet)
                    }
                    Text(definition).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
            }

            if let context = word.context {
                HStack(alignment: .top, spacing: 8) {
                    Capsule().fill(Theme.brand).frame(width: 3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context).italic().foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                        if let source = word.sourceName {
                            Text(source).font(.caption).foregroundStyle(Theme.textDim).lineLimit(1)
                        }
                    }
                }
                .font(.callout)
            }

            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button { Pronouncer.shared.say(word.word) } label: { Image(systemName: "speaker.wave.2.fill") }
                    .buttonStyle(IconButtonStyle(size: 28))
                    .help("Ouvir a pronúncia")
                if let path = word.sourcePath, FileManager.default.fileExists(atPath: path) {
                    Button("Ir para o trecho", systemImage: "play.fill") {
                        model.open(URL(fileURLWithPath: path), at: word.sourceTime ?? 0)
                    }
                    .buttonStyle(GlassButtonStyle())
                }
                Spacer()
                if isHovered {
                    Button { store.remove(word.key) } label: { Image(systemName: "trash") }
                        .buttonStyle(IconButtonStyle(size: 28, tint: Theme.textDim))
                        .help("Remover da lista")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .glassCard(highlighted: isHovered)
        .onHover { isHovered = $0 }
        .textSelection(.enabled)
    }
}

/// "Revisar agora", "Revisão em 3 dias" or "Dominada".
private struct ReviewStatus: View {
    let review: ReviewState?

    var body: some View {
        Group {
            if let review, review.isMastered {
                Chip(text: "Dominada", systemImage: "checkmark.seal.fill", color: scoreColor(100))
            } else if let review, review.due > Date() {
                Chip(text: "Revisão \(review.due.formatted(.relative(presentation: .named)))", systemImage: "clock", color: Theme.textDim)
            } else {
                Chip(text: "Revisar agora", systemImage: "bolt.fill", color: Theme.orange)
            }
        }
    }
}

/// Search box on glass.
struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textDim)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textDim)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 12)
    }
}

/// Icon, title and explanation for an empty screen.
struct EmptyState: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .semibold))
                .gradientForeground(Theme.brand)
            Text(title).font(.title3.bold())
            Text(text).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
