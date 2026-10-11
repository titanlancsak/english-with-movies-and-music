import Foundation

public enum AppVersion {
    /// "v1.10.0" is newer than "1.9.2"; anything that is not a version is never newer.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = numbers(candidate), b = numbers(current)
        guard !a.isEmpty, !b.isEmpty else { return false }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func numbers(_ version: String) -> [Int] {
        let trimmed = version.trimmingCharacters(in: .whitespaces).drop { $0 == "v" || $0 == "V" }
        let parts = trimmed.split(separator: ".").map { Int($0) }
        return parts.contains(nil) ? [] : parts.compactMap { $0 }
    }
}

/// Black bars in covers: reads ffmpeg's cropdetect output.
public enum CropDetect {
    /// The last "crop=W:H:X:Y" suggestion, or nil when there is nothing worth cropping.
    public static func crop(fromFFmpegOutput output: String, width: Int? = nil, height: Int? = nil) -> String? {
        let regex = try! NSRegularExpression(pattern: #"crop=(\d+):(\d+):(\d+):(\d+)"#)
        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.matches(in: output, range: range).last else { return nil }
        let values = (1...4).compactMap { Range(match.range(at: $0), in: output).flatMap { Int(output[$0]) } }
        guard values.count == 4, values[0] > 32, values[1] > 32 else { return nil }
        // A dark scene can make cropdetect suggest a small piece of the frame; only accept
        // results no wider than a cinema film (2.6:1).
        guard Double(values[1]) >= Double(values[0]) * 0.38 else { return nil }
        if let width, let height, values[0] >= width - 4, values[1] >= height - 4 { return nil }
        return "crop=" + values.map(String.init).joined(separator: ":")
    }
}
