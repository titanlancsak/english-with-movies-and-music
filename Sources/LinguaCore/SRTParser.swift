import Foundation

/// Parses .srt subtitle files. SRT only has timing per line, so word timings are
/// estimated by spreading the line duration proportionally to word length.
public enum SRTParser {
    public static func parse(_ contents: String) -> Transcript {
        let normalized = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        let blocks = normalized.components(separatedBy: "\n\n")

        var lines: [TranscriptLine] = []
        for block in blocks {
            let rows = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timeRow = rows.firstIndex(where: { $0.contains("-->") }) else { continue }
            let times = rows[timeRow].components(separatedBy: "-->")
            guard times.count == 2,
                  let start = parseTime(times[0]),
                  let end = parseTime(times[1]) else { continue }

            let text = rows[(timeRow + 1)...]
                .joined(separator: " ")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            let tokens = text.split(separator: " ").map(String.init)
            guard !tokens.isEmpty else { continue }

            lines.append(TranscriptLine(
                id: lines.count,
                start: start,
                end: end,
                words: spread(tokens, from: start, to: end)
            ))
        }
        return Transcript(lines: lines)
    }

    /// "00:01:02,500" -> 62.5
    static func parseTime(_ raw: String) -> Double? {
        let parts = raw.trimmingCharacters(in: .whitespaces)
            .split(separator: " ").first?
            .replacingOccurrences(of: ",", with: ".")
            .split(separator: ":") ?? []
        guard parts.count == 3,
              let h = Double(parts[0]), let m = Double(parts[1]), let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }

    private static func spread(_ tokens: [String], from start: Double, to end: Double) -> [TimedWord] {
        let total = Double(tokens.reduce(0) { $0 + $1.count + 1 })
        let duration = max(end - start, 0.1)
        var cursor = start
        return tokens.map { token in
            let length = duration * Double(token.count + 1) / total
            defer { cursor += length }
            return TimedWord(text: token, start: cursor, end: cursor + length)
        }
    }
}
