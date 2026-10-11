import Foundation
import LinguaCore

enum MediaToolError: LocalizedError {
    case toolMissing(String)
    case failed(String, String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .toolMissing(let name):
            "Não encontrei o programa \"\(name)\". Instale com: brew install ffmpeg whisper-cpp yt-dlp"
        case .failed(let name, let output):
            "\(name) falhou:\n\(output.suffix(600))"
        case .cancelled:
            "Cancelado."
        }
    }
}

/// Wraps the command line tools the app relies on: ffmpeg and whisper.cpp (whisper-cli).
final class MediaTools: @unchecked Sendable {
    private let lock = NSLock()
    private var running: Process?
    private var isCancelled = false

    static func locate(_ name: String) -> URL? {
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin"] + pathDirs
        return dirs
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    func cancel() {
        lock.withLock {
            isCancelled = true
            running?.terminate()
        }
    }

    /// Converts the media's audio track to 16 kHz mono WAV, the format Whisper expects.
    func extractAudio(from media: URL, to wav: URL) async throws {
        try await run("ffmpeg", [
            "-y", "-loglevel", "error", "-i", media.path,
            "-vn", "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", wav.path,
        ])
    }

    /// Repackages formats AVPlayer cannot open (e.g. .mkv) into .mp4.
    /// With `transcodeVideo`, also converts the picture to H.264 (for codecs like VP9 or AV1).
    func convertToMP4(_ media: URL, to output: URL, transcodeVideo: Bool) async throws {
        let video = transcodeVideo ? ["-c:v", "h264_videotoolbox", "-b:v", "6M"] : ["-c:v", "copy"]
        try await run("ffmpeg", [
            "-y", "-loglevel", "error", "-i", media.path,
            "-map", "0:v:0?", "-map", "0:a:0?", "-sn",
        ] + video + ["-c:a", "aac", "-movflags", "+faststart", output.path])
    }

    /// Downloads a YouTube (or other yt-dlp supported) video as .mp4 into `folder`.
    /// Returns the downloaded file.
    func downloadVideo(from link: String, to folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let output = OutputBuffer()
        try await run("yt-dlp", [
            "--no-playlist", "--newline", "--progress", "--no-update",
            // Prefer H.264 + AAC (plays natively on every Mac), up to 1080p.
            "-S", "res:1080,vcodec:h264,acodec:aac",
            "--merge-output-format", "mp4",
            "--ffmpeg-location", Self.locate("ffmpeg")?.path ?? "ffmpeg",
            "-o", folder.appendingPathComponent("%(title).120B [%(id)s].%(ext)s").path,
            "--print", "after_move:FILE:%(filepath)s",
            link,
        ]) { line in
            // "[download]  42.3% of 120.00MiB at 3.2MiB/s ETA 00:30"
            if line.hasPrefix("FILE:") {
                output.append(String(line.dropFirst(5)))
            } else if line.hasPrefix("[download]"), let percent = line.split(separator: " ").first(where: { $0.hasSuffix("%") }) {
                if let value = Double(percent.dropLast()) { progress(value / 100) }
            }
        }
        let path = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            throw MediaToolError.failed("yt-dlp", "O download terminou, mas o arquivo não foi encontrado.")
        }
        return URL(fileURLWithPath: path)
    }

    /// Runs Whisper and returns the parsed transcript.
    func transcribe(wav: URL, model: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> Transcript {
        let outputBase = wav.deletingPathExtension()
        let threads = max(2, ProcessInfo.processInfo.activeProcessorCount - 2)
        try await run("whisper-cli", [
            "-m", model.path, "-f", wav.path, "-l", "en",
            "-t", String(threads), "-ojf", "-of", outputBase.path, "-pp",
            // Suppress non-speech tokens such as "[Music]" or "(applause)".
            "--suppress-nst",
        ]) { line in
            // whisper-cli prints e.g. "whisper_print_progress_callback: progress =  42%"
            guard let range = line.range(of: "progress =") else { return }
            let digits = line[range.upperBound...].filter(\.isNumber)
            if let percent = Double(digits) { progress(percent / 100) }
        }
        let data = try Data(contentsOf: outputBase.appendingPathExtension("json"))
        return try WhisperJSONParser.parse(data)
    }

    // MARK: - Process

    private func run(_ tool: String, _ arguments: [String], onOutput: (@Sendable (String) -> Void)? = nil) async throws {
        guard let executable = Self.locate(tool) else { throw MediaToolError.toolMissing(tool) }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        let collected = OutputBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = String(decoding: handle.availableData, as: UTF8.self)
            collected.append(chunk)
            chunk.split(whereSeparator: \.isNewline).forEach { onOutput?(String($0)) }
        }

        try lock.withLock {
            if isCancelled { throw MediaToolError.cancelled }
            running = process
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { [weak self] process in
                pipe.fileHandleForReading.readabilityHandler = nil
                let cancelled = self?.lock.withLock { self?.isCancelled ?? false } ?? false
                if cancelled {
                    continuation.resume(throwing: MediaToolError.cancelled)
                } else if process.terminationStatus != 0 {
                    continuation.resume(throwing: MediaToolError.failed(tool, collected.text))
                } else {
                    continuation.resume()
                }
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    func append(_ text: String) {
        lock.withLock { storage += text }
    }

    var text: String { lock.withLock { storage } }
}
