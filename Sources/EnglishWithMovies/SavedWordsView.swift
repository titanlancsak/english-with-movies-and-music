import LinguaCore
import SwiftUI
import UniformTypeIdentifiers

/// Window listing the saved words.
struct SavedWordsView: View {
    @EnvironmentObject private var store: SavedWordsStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @ViewState private var query = ""
    @ViewState private var exportError: String?

    var body: some View {
        let words = store.list.filtered(by: query)
        Group {
            if store.list.words.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Nenhuma palavra salva ainda").font(.title3.bold())
                    Text("Clique numa palavra da legenda e toque em 🔖 para guardá-la aqui.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(words) { word in
                    SavedWordRow(word: word)
                        .contextMenu {
                            Button("Remover", role: .destructive) { store.remove(word.key) }
                        }
                }
                .overlay {
                    if words.isEmpty { Text("Nada encontrado para \"\(query)\"").foregroundStyle(.secondary) }
                }
            }
        }
        .searchable(text: $query, prompt: "Buscar palavra, tradução, significado ou frase")
        .toolbar {
            ToolbarItem {
                Text("\(store.list.words.count) palavra\(store.list.words.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }
            ToolbarItem {
                Button("Revisar (\(store.list.due().count))", systemImage: "rectangle.on.rectangle.angled") {
                    openWindow(id: "review")
                }
                .help("Revisar as palavras com cartões (⇧⌘R)")
                .disabled(store.list.words.isEmpty)
            }
            ToolbarItem {
                Button("Exportar CSV", systemImage: "square.and.arrow.up", action: export)
                    .help("Exportar para planilha ou Anki")
                    .disabled(store.list.words.isEmpty)
            }
        }
        .alert("Não foi possível exportar", isPresented: Binding(
            get: { exportError != nil }, set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(exportError ?? "")
        }
        .frame(minWidth: 460, minHeight: 400)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(word.word).font(.title3.bold())
                if let translation = word.translation {
                    Text("· \(translation)").font(.title3)
                }
                if let phonetic = word.phonetic {
                    Text(phonetic).foregroundStyle(.secondary)
                }
                if let partOfSpeech = word.partOfSpeech {
                    Text(partOfSpeech).font(.caption.italic()).foregroundStyle(.secondary)
                }
                Spacer()
                ReviewStatus(review: word.review)
                Button { Pronouncer.shared.say(word.word) } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .help("Ouvir a pronúncia")
                Button { store.remove(word.key) } label: {
                    Image(systemName: "trash")
                }
                .help("Remover da lista")
            }
            .buttonStyle(.borderless)

            if let definition = word.definition {
                Text(definition).fixedSize(horizontal: false, vertical: true)
            }

            if let context = word.context {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "text.quote").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context).italic().fixedSize(horizontal: false, vertical: true)
                        if let source = word.sourceName {
                            Text(source).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let path = word.sourcePath, FileManager.default.fileExists(atPath: path) {
                        Button("Ir para o trecho") {
                            model.open(URL(fileURLWithPath: path), at: word.sourceTime ?? 0)
                            NSApp.windows.first { $0.identifier?.rawValue != "saved-words" && $0.canBecomeMain }?
                                .makeKeyAndOrderFront(nil)
                        }
                        .controlSize(.small)
                    }
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 6)
        .textSelection(.enabled)
    }
}

/// "Revisar agora", "Revisão em 3 dias" or "Dominada".
private struct ReviewStatus: View {
    let review: ReviewState?

    var body: some View {
        Group {
            if let review, review.isMastered {
                Label("Dominada", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else if let review, review.due > Date() {
                Text("Revisão \(review.due.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary)
            } else {
                Text("Revisar agora").foregroundStyle(.orange)
            }
        }
        .font(.caption)
    }
}
