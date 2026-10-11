import Foundation

/// The most common English words, to highlight the uncommon ones in the subtitles.
public enum CommonWords {
    static let words: Set<String> = Set(data.split(separator: " ").map(String.init))

    /// True for a word outside the 5,000 most common ones (counting forms such as "running" -> "run").
    /// Capitalized words in the middle of a sentence are taken as names and skipped.
    public static func isUncommon(_ word: String, atSentenceStart: Bool = false) -> Bool {
        let key = WordNormalizer.lookupKey(word)
        guard key.count >= 3, key.allSatisfy({ $0.isLetter || $0 == "'" }) else { return false }
        if !atSentenceStart, let first = word.first(where: \.isLetter), first.isUppercase { return false }
        return !WordNormalizer.candidates(for: word).contains(where: words.contains)
    }
}
