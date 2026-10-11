import Foundation

/// A word the user saved to review later, with the sentence where it was found.
public struct SavedWord: Codable, Hashable, Identifiable, Sendable {
    public var id: String { key }
    /// Normalized form used to compare words ("Don't!" -> "don't").
    public var key: String
    public var word: String
    public var phonetic: String?
    public var partOfSpeech: String?
    public var definition: String?
    /// The subtitle line where the word was clicked.
    public var context: String?
    public var sourcePath: String?
    public var sourceTime: Double?
    public var dateAdded: Date

    public init(word: String, phonetic: String? = nil, partOfSpeech: String? = nil, definition: String? = nil,
                context: String? = nil, sourcePath: String? = nil, sourceTime: Double? = nil, dateAdded: Date = Date()) {
        self.key = WordNormalizer.lookupKey(word)
        self.word = word
        self.phonetic = phonetic
        self.partOfSpeech = partOfSpeech
        self.definition = definition
        self.context = context
        self.sourcePath = sourcePath
        self.sourceTime = sourceTime
        self.dateAdded = dateAdded
    }

    public var sourceName: String? {
        sourcePath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
    }
}

/// The saved words, newest first.
public struct WordList: Codable, Hashable, Sendable {
    public private(set) var words: [SavedWord] = []

    public init(words: [SavedWord] = []) {
        self.words = words
    }

    public var keys: Set<String> { Set(words.map(\.key)) }

    public func contains(_ word: String) -> Bool {
        let key = WordNormalizer.lookupKey(word)
        return words.contains { $0.key == key }
    }

    /// Adds the word at the top; saving it again replaces the old entry.
    public mutating func add(_ word: SavedWord) {
        guard !word.key.isEmpty else { return }
        remove(word.key)
        words.insert(word, at: 0)
    }

    public mutating func remove(_ word: String) {
        let key = WordNormalizer.lookupKey(word)
        words.removeAll { $0.key == key }
    }

    public func filtered(by query: String) -> [SavedWord] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return words }
        return words.filter {
            $0.word.localizedCaseInsensitiveContains(query)
                || ($0.definition ?? "").localizedCaseInsensitiveContains(query)
                || ($0.context ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    /// CSV for spreadsheets or flashcard apps such as Anki.
    public func csv() -> String {
        let header = ["word", "phonetic", "part of speech", "definition", "sentence", "source"]
        let rows = words.map { word in
            [word.word, word.phonetic, word.partOfSpeech, word.definition, word.context, word.sourceName]
                .map { Self.csvField($0 ?? "") }
                .joined(separator: ",")
        }
        return ([header.joined(separator: ",")] + rows).joined(separator: "\n") + "\n"
    }

    static func csvField(_ value: String) -> String {
        guard value.contains(where: { ",\"\n\r".contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
