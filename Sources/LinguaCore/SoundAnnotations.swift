import Foundation

/// Removes descriptions of sounds from subtitles, e.g. "[Music]", "(background music playing)",
/// "*sighs*" and "♪". Whisper and hearing-impaired subtitles add these; they are not speech.
public enum SoundAnnotationFilter {
    private static let pairs: [Character: Character] = ["[": "]", "(": ")", "*": "*"]
    private static let musicSymbols = CharacterSet(charactersIn: "♪♫♬🎵🎶")
    /// An opening "(" not closed within this many words is treated as normal text.
    private static let maxAnnotationWords = 12

    public static func clean(_ words: [TimedWord]) -> [TimedWord] {
        cleanIndexed(words).map(\.word)
    }

    /// Like `clean`, also returning each kept word's position in the input.
    /// Works character by character, because Whisper often glues annotations to words
    /// ("out.[MUSIC", "PLAYING][MUSIC").
    static func cleanIndexed(_ words: [TimedWord]) -> [(index: Int, word: TimedWord)] {
        var closing: Character?
        var result: [(index: Int, word: TimedWord)] = []

        for (index, word) in words.enumerated() {
            let characters = Array(word.text)
            var kept = ""
            for (offset, character) in characters.enumerated() {
                if let close = closing {
                    if character == close { closing = nil }
                    continue
                }
                // "*" only starts an annotation at the beginning of a word ("*sighs*", not "f*ck").
                if let close = pairs[character], character != "*" || offset == 0,
                   isClosed(close, after: offset, in: characters, wordIndex: index, words: words) {
                    closing = close
                    continue
                }
                kept.append(character)
            }

            let text = kept.unicodeScalars.filter { !musicSymbols.contains($0) }.map(String.init).joined()
                .trimmingCharacters(in: .whitespaces)
            // Nothing but punctuation left (e.g. the "." after "[Music].").
            guard text.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else { continue }
            var cleaned = word
            cleaned.text = text
            result.append((index, cleaned))
        }
        return result
    }

    /// Whether `close` appears later in this word or within the next few words.
    /// An opening "(" that is never closed is probably real speech and is kept.
    private static func isClosed(_ close: Character, after offset: Int, in characters: [Character],
                                 wordIndex: Int, words: [TimedWord]) -> Bool {
        if characters[(offset + 1)...].contains(close) { return true }
        return words[(wordIndex + 1)...].prefix(maxAnnotationWords).contains { $0.text.contains(close) }
    }
}

extension Transcript {
    /// The same transcript without sound descriptions; lines left empty are removed.
    public func removingSoundAnnotations() -> Transcript {
        // Filter all words at once so an annotation spanning two lines is handled.
        let lineOfWord = lines.indices.flatMap { index in Array(repeating: index, count: lines[index].words.count) }
        var wordsByLine = Array(repeating: [TimedWord](), count: lines.count)
        for kept in SoundAnnotationFilter.cleanIndexed(lines.flatMap(\.words)) {
            wordsByLine[lineOfWord[kept.index]].append(kept.word)
        }

        var result: [TranscriptLine] = []
        for words in wordsByLine {
            guard let first = words.first, let last = words.last else { continue }
            result.append(TranscriptLine(id: result.count, start: first.start, end: last.end, words: words))
        }
        return Transcript(lines: result)
    }
}
