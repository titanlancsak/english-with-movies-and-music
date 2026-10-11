import CryptoKit
import Foundation
import LinguaCore

/// Folders under ~/Library/Application Support/EnglishWithMovies
enum AppFolders {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("EnglishWithMovies", isDirectory: true)
    }()

    static let models = folder("models")
    static let transcripts = folder("transcripts")
    static let work = folder("work")
    /// Temporary microphone recordings, deleted when the practice sheet closes.
    static let practice = folder("practice")
    /// Library covers.
    static let thumbnails = folder("thumbnails")

    /// Videos downloaded from links, kept where the user can find them.
    static let downloads: URL = {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        let url = movies.appendingPathComponent("English with Movies", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static func folder(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Deleting media together with everything the app derived from it.
enum MediaFiles {
    /// Deletes the file, its converted copy and its transcripts.
    static func delete(_ url: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        // Keys depend on the file's size and date, so compute them before deleting it.
        let converted = AppFolders.work.appendingPathComponent(TranscriptCache.key(for: url, model: "convert") + ".mp4")
        let transcripts = WhisperModel.allCases.map {
            AppFolders.transcripts.appendingPathComponent(TranscriptCache.key(for: url, model: $0.rawValue) + ".json")
        }
        ([url, converted] + transcripts).forEach { try? fileManager.removeItem(at: $0) }
    }

    /// yt-dlp pieces of an unfinished download, e.g. "x.mp4.part" or "x.f137.mp4".
    static func isPartialDownload(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasSuffix(".part") || name.hasSuffix(".ytdl")
            || name.range(of: #"\.f\d+\.[a-z0-9]+$"#, options: .regularExpression) != nil
    }

    /// Removes pieces left by interrupted downloads (called when the app quits).
    static func cleanDownloadLeftovers() {
        let files = (try? FileManager.default.contentsOfDirectory(at: AppFolders.downloads, includingPropertiesForKeys: nil)) ?? []
        for file in files where isPartialDownload(file) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

/// Saves transcripts so each movie/song is only transcribed once.
enum TranscriptCache {
    static func key(for media: URL, model: String) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: media.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let raw = "\(media.path)|\(size)|\(modified)|\(model)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func load(key: String) -> Transcript? {
        let url = AppFolders.transcripts.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Also cleans transcripts saved before sound annotations were filtered.
        return (try? JSONDecoder().decode(Transcript.self, from: data))?.removingSoundAnnotations()
    }

    static func save(_ transcript: Transcript, key: String) {
        let url = AppFolders.transcripts.appendingPathComponent("\(key).json")
        if let data = try? JSONEncoder().encode(transcript) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Whisper models (free, from https://huggingface.co/ggerganov/whisper.cpp).
enum WhisperModel: String, CaseIterable, Identifiable {
    case base = "ggml-base.en.bin"
    case small = "ggml-small.en.bin"
    case medium = "ggml-medium.en-q5_0.bin"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .base: "Rápido (base, 148 MB)"
        case .small: "Equilibrado (small, 488 MB)"
        case .medium: "Preciso (medium, 539 MB)"
        }
    }

    var localURL: URL { AppFolders.models.appendingPathComponent(rawValue) }
    var isDownloaded: Bool { FileManager.default.fileExists(atPath: localURL.path) }
    var remoteURL: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(rawValue)")! }
}

/// Downloads a model while reporting progress.
final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private var progress: (@Sendable (Double) -> Void)?
    private var destination: URL?

    func download(_ model: WhisperModel, progress: @escaping @Sendable (Double) -> Void) async throws {
        self.progress = progress
        self.destination = model.localURL
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        _ = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: model.remoteURL).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let destination else { return }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(returning: destination)
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
