import Foundation

/// Parses the "full JSON" output of whisper.cpp (`whisper-cli -ojf`) into a `Transcript`.
public enum WhisperJSONParser {
    private struct Root: Decodable { let transcription: [Segment] }
    private struct Segment: Decodable { let tokens: [Token]? }
    private struct Token: Decodable {
        let text: String
        let offsets: Offsets
    }
    private struct Offsets: Decodable {
        let from: Int
        let to: Int
    }

    public static func parse(_ data: Data) throws -> Transcript {
        // Tokens can split multi-byte characters (e.g. "♪"), producing invalid UTF-8.
        // Decoding lossily replaces those bytes so JSONDecoder accepts the file.
        let cleaned = Data(String(decoding: data, as: UTF8.self).utf8)
        let root = try JSONDecoder().decode(Root.self, from: cleaned)

        var words: [TimedWord] = []
        var segmentBreaks: Set<Int> = []

        for segment in root.transcription {
            for token in segment.tokens ?? [] {
                // Special tokens look like "[_BEG_]" or "[_TT_123]".
                if token.text.hasPrefix("[_") { continue }
                let text = token.text.replacingOccurrences(of: "\u{FFFD}", with: "")
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }

                let start = Double(token.offsets.from) / 1000
                let end = Double(token.offsets.to) / 1000
                let startsNewWord = text.hasPrefix(" ") && !isPunctuation(trimmed)

                if startsNewWord || words.isEmpty {
                    words.append(TimedWord(text: trimmed, start: start, end: end))
                } else {
                    // Sub-word piece or punctuation: glue to the previous word.
                    words[words.count - 1].text += trimmed
                    words[words.count - 1].end = max(words[words.count - 1].end, end)
                }
            }
            if !words.isEmpty { segmentBreaks.insert(words.count - 1) }
        }

        return Transcript(lines: LineBuilder.build(words: words, segmentBreaks: segmentBreaks))
            .removingSoundAnnotations()
    }

    private static func isPunctuation(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
    }
}
