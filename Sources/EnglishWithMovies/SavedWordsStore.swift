import Foundation
import LinguaCore

/// Keeps the saved word list on disk (~/Library/Application Support/EnglishWithMovies/saved-words.json).
@MainActor
final class SavedWordsStore: ObservableObject {
    @Published private(set) var list: WordList
    /// Normalized keys, for fast highlighting in the transcript.
    @Published private(set) var keys: Set<String>

    private let fileURL = AppFolders.root.appendingPathComponent("saved-words.json")

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let saved = (try? Data(contentsOf: fileURL)).flatMap { try? decoder.decode(WordList.self, from: $0) }
        let initial = saved ?? WordList()
        list = initial
        keys = initial.keys
    }

    func contains(_ word: String) -> Bool {
        keys.contains(WordNormalizer.lookupKey(word))
    }

    func add(_ word: SavedWord) {
        list.add(word)
        persist()
    }

    func remove(_ word: String) {
        list.remove(word)
        persist()
    }

    func exportCSV(to url: URL) throws {
        try list.csv().write(to: url, atomically: true, encoding: .utf8)
    }

    private func persist() {
        keys = list.keys
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(list) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
