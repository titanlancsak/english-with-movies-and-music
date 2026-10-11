import Foundation

public enum WordNormalizer {
    /// Lowercases and strips surrounding punctuation: "“Don’t!”" -> "don't".
    public static func lookupKey(_ word: String) -> String {
        word
            .replacingOccurrences(of: "’", with: "'")
            .lowercased()
            .trimmingCharacters(in: CharacterSet.letters.inverted)
    }

    /// Base forms to try when the exact word is not in the dictionary,
    /// e.g. "let's" -> "let", "running" -> "runn", "run".
    public static func candidates(for word: String) -> [String] {
        let key = lookupKey(word)
        guard !key.isEmpty else { return [] }
        var result = [key]

        func add(_ value: String) {
            if value.count >= 2, !result.contains(value) { result.append(value) }
        }

        for suffix in ["n't", "'s", "'re", "'ll", "'ve", "'d", "'m"] where key.hasSuffix(suffix) {
            add(String(key.dropLast(suffix.count)))
        }
        if key.hasSuffix("ies") { add(String(key.dropLast(3)) + "y") }
        if key.hasSuffix("ied") { add(String(key.dropLast(3)) + "y") }
        if key.hasSuffix("ing") {
            let stem = String(key.dropLast(3))
            add(stem)
            add(stem + "e")
            if let last = stem.last, stem.dropLast().last == last { add(String(stem.dropLast())) }
        }
        if key.hasSuffix("ed") {
            let stem = String(key.dropLast(2))
            add(stem)
            add(String(key.dropLast(1)))
            if let last = stem.last, stem.dropLast().last == last { add(String(stem.dropLast())) }
        }
        if key.hasSuffix("es") { add(String(key.dropLast(2))) }
        if key.hasSuffix("s") { add(String(key.dropLast(1))) }
        return result
    }
}

public struct DictionaryEntry: Hashable, Sendable {
    public struct Sense: Hashable, Sendable {
        public var partOfSpeech: String
        public var definition: String
    }

    public var word: String
    public var phonetic: String?
    public var senses: [Sense]
    /// At most 3 example sentences.
    public var examples: [String]
}

public enum DictionaryError: Error {
    case notFound
}

/// Looks up words in an offline dictionary first (on macOS, the one built into the system),
/// then in the free Dictionary API (https://dictionaryapi.dev, no key needed).
public actor DictionaryService {
    public static let maxExamples = 3

    private var cache: [String: DictionaryEntry] = [:]
    private let session: URLSession
    private let offlineLookup: (@Sendable (String) -> DictionaryEntry?)?

    public init(session: URLSession = .shared, offlineLookup: (@Sendable (String) -> DictionaryEntry?)? = nil) {
        self.session = session
        self.offlineLookup = offlineLookup
    }

    public func lookup(_ word: String) async throws -> DictionaryEntry {
        let candidates = WordNormalizer.candidates(for: word)
        for candidate in candidates {
            if let cached = cache[candidate] { return cached }
            if let entry = offlineLookup?(candidate) {
                cache[candidate] = entry
                return entry
            }
        }
        for candidate in candidates {
            if let entry = try? await fetch(candidate) {
                cache[candidate] = entry
                return entry
            }
        }
        throw DictionaryError.notFound
    }

    private func fetch(_ word: String) async throws -> DictionaryEntry? {
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)") else { return nil }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try Self.parse(data)
    }

    // MARK: - Parsing

    private struct APIEntry: Decodable {
        let word: String
        let phonetic: String?
        let phonetics: [APIPhonetic]?
        let meanings: [APIMeaning]
    }
    private struct APIPhonetic: Decodable { let text: String? }
    private struct APIMeaning: Decodable {
        let partOfSpeech: String
        let definitions: [APIDefinition]
    }
    private struct APIDefinition: Decodable {
        let definition: String
        let example: String?
    }

    public static func parse(_ data: Data) throws -> DictionaryEntry? {
        let entries = try JSONDecoder().decode([APIEntry].self, from: data)
        guard let first = entries.first else { return nil }

        var senses: [DictionaryEntry.Sense] = []
        var examples: [String] = []
        for meaning in entries.flatMap(\.meanings) {
            for (i, definition) in meaning.definitions.enumerated() {
                if i < 2, senses.count < 5 {
                    senses.append(.init(partOfSpeech: meaning.partOfSpeech, definition: definition.definition))
                }
                if let example = definition.example, examples.count < maxExamples, !examples.contains(example) {
                    examples.append(example)
                }
            }
        }

        let phonetic = first.phonetic ?? first.phonetics?.compactMap(\.text).first
        return DictionaryEntry(word: first.word, phonetic: phonetic, senses: senses, examples: examples)
    }
}

/// Parses the plain-text definitions returned by the macOS dictionary (DCSCopyTextDefinition).
/// Format: "word | phonetic | noun definition: example | example. • other sense: example. verb 1 ..."
public enum SystemDictionaryParser {
    private static let partsOfSpeech = [
        "noun", "verb", "adjective", "adverb", "pronoun", "preposition",
        "conjunction", "exclamation", "determiner", "abbreviation",
    ]
    private static let sectionMarkers = [" ORIGIN ", " DERIVATIVES ", " PHRASES ", " PHRASAL VERBS ", " USAGE "]

    /// - Parameter fallbackWord: used when the headword cannot be read from the text.
    public static func parse(_ text: String, fallbackWord: String = "") -> DictionaryEntry? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for marker in sectionMarkers {
            if let range = body.range(of: marker) { body = String(body[..<range.lowerBound]) }
        }

        // A part of speech starts a block when it follows the header or the end of a sense.
        let pattern = "(?:^|(?<=[.)|\\]] ))(" + partsOfSpeech.joined(separator: "|") + ") "
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: ns.length))
        guard let first = matches.first else { return nil }

        let header = ns.substring(to: first.range.location)
        let headerParts = header.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        let word = (headerParts.first ?? "")
            .replacingOccurrences(of: "·", with: "")
            .trimmingCharacters(in: CharacterSet.letters.union(CharacterSet(charactersIn: "'-")).inverted)
        let phonetic = headerParts.count > 2 && !headerParts[1].isEmpty ? "/\(headerParts[1])/" : nil

        var senses: [DictionaryEntry.Sense] = []
        var examples: [String] = []
        for (i, match) in matches.enumerated() {
            let partOfSpeech = ns.substring(with: match.range(at: 1))
            let start = match.range.location + match.range.length
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            let block = ns.substring(with: NSRange(location: start, length: end - start))

            var sensesInBlock = 0
            for rawSense in splitSenses(block) {
                let pieces = rawSense.split(separator: ":", maxSplits: 1).map(String.init)
                let definition = clean(pieces[0])
                // A leading grammar note such as "[with object]" leaves an empty piece.
                guard !definition.isEmpty else { continue }
                if sensesInBlock < 2, senses.count < 5 {
                    senses.append(.init(partOfSpeech: partOfSpeech, definition: definition))
                }
                sensesInBlock += 1
                if pieces.count > 1 {
                    for example in pieces[1].components(separatedBy: " | ") {
                        let sentence = clean(example)
                        if !sentence.isEmpty, examples.count < DictionaryService.maxExamples {
                            examples.append(sentence.prefix(1).uppercased() + sentence.dropFirst())
                        }
                    }
                }
            }
        }
        guard !senses.isEmpty else { return nil }
        return DictionaryEntry(word: word.isEmpty ? fallbackWord : word, phonetic: phonetic, senses: senses, examples: examples)
    }

    /// Splits on bullets ("•") and numbered senses (" 1 ", " 2 ").
    private static func splitSenses(_ block: String) -> [String] {
        block
            .replacingOccurrences(of: "(^| )\\d{1,2} (?=[A-Za-z(\\[])", with: " • ", options: .regularExpression)
            .components(separatedBy: "•")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Removes grammar notes like "[with object]" or "(plural journeys)" and trailing dots.
    private static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^\\s*\\([^)]*\\)", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".;,: "))
    }
}
