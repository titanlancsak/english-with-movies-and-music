import AppKit
import AVFoundation
import CryptoKit
import Foundation

/// A movie or song shown in the library.
struct LibraryItem: Identifiable, Hashable {
    var id: String { url.path }
    var url: URL
    var title: String
    var isAudio: Bool
    /// Downloaded from a link (lives in the app's downloads folder).
    var isDownload: Bool
    var size: Int64
    var duration: Double?
    /// Where playback stopped last time, in seconds.
    var position: Double?
    var lastOpened: Date?
    var added: Date
    var hasTranscript: Bool

    /// 0...1 when partially watched.
    var progress: Double? {
        guard let position, let duration, duration > 0 else { return nil }
        return min(1, position / duration)
    }

    var isInProgress: Bool {
        guard let progress else { return false }
        return progress > 0.02 && progress < 0.95
    }
}

/// Knows what is in the library: the downloads folder plus files opened before.
/// Saves when each item was opened and where playback stopped.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var items: [LibraryItem] = []
    @Published private(set) var thumbnails: [String: NSImage] = [:]

    private struct Record: Codable {
        var lastOpened: Date?
        var position: Double?
        var duration: Double?
    }

    private var records: [String: Record] = [:]
    private var thumbnailAttempts: Set<String> = []
    private var lastSave = Date.distantPast
    private let fileURL = AppFolders.root.appendingPathComponent("library.json")

    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi"]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "ogg", "opus", "aiff", "aif"]

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? Data(contentsOf: fileURL)).flatMap { try? decoder.decode([String: Record].self, from: $0) } ?? [:]
        refresh()
    }

    // MARK: - Rows

    var featured: LibraryItem? { items.first }
    var continueWatching: [LibraryItem] { items.filter(\.isInProgress) }
    var downloads: [LibraryItem] { items.filter(\.isDownload) }
    var videos: [LibraryItem] { items.filter { !$0.isAudio && !$0.isDownload } }
    var music: [LibraryItem] { items.filter(\.isAudio) }
    var downloadsSize: Int64 { downloads.reduce(0) { $0 + $1.size } }

    // MARK: - Updating

    /// Rescans the downloads folder and drops files that no longer exist.
    func refresh() {
        let fileManager = FileManager.default
        let downloaded = ((try? fileManager.contentsOfDirectory(
            at: AppFolders.downloads, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { Self.isMedia($0) && !MediaFiles.isPartialDownload($0) }
            .map(\.path)

        var paths = Set(downloaded)
        for path in records.keys where fileManager.fileExists(atPath: path) {
            paths.insert(path)
        }

        items = paths.map(makeItem).sorted {
            ($0.lastOpened ?? $0.added) > ($1.lastOpened ?? $1.added)
        }
        for item in items where thumbnails[item.id] == nil {
            loadOrCreateThumbnail(for: item)
        }
    }

    func recordOpened(_ url: URL) {
        records[url.path, default: Record()].lastOpened = Date()
        save()
        refresh()
    }

    /// Called during playback; saved to disk at most every 10 seconds.
    func updatePosition(_ url: URL, seconds: Double, duration: Double?) {
        guard seconds.isFinite else { return }
        records[url.path, default: Record()].position = seconds
        if let duration, duration.isFinite, duration > 0 { records[url.path]?.duration = duration }
        if Date().timeIntervalSince(lastSave) > 10 { save() }
    }

    /// Removes a file opened from elsewhere from the library (the file is kept).
    func forget(_ item: LibraryItem) {
        records.removeValue(forKey: item.id)
        save()
        refresh()
    }

    /// Deletes a downloaded file with its converted copy, transcripts and cover.
    func delete(_ item: LibraryItem) {
        try? FileManager.default.removeItem(at: thumbnailURL(for: item.url))
        MediaFiles.delete(item.url)
        records.removeValue(forKey: item.id)
        thumbnails.removeValue(forKey: item.id)
        save()
        refresh()
    }

    func save() {
        lastSave = Date()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(records) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Items

    static func isMedia(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return videoExtensions.contains(ext) || audioExtensions.contains(ext)
    }

    private func makeItem(_ path: String) -> LibraryItem {
        let url = URL(fileURLWithPath: path)
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let record = records[path]
        let isDownload = url.deletingLastPathComponent().standardizedFileURL == AppFolders.downloads.standardizedFileURL
        return LibraryItem(
            url: url,
            title: Self.cleanTitle(url),
            isAudio: Self.audioExtensions.contains(url.pathExtension.lowercased()),
            isDownload: isDownload,
            size: (attributes?[.size] as? NSNumber)?.int64Value ?? 0,
            duration: record?.duration,
            position: record?.position,
            lastOpened: record?.lastOpened,
            added: (attributes?[.creationDate] as? Date) ?? .distantPast,
            hasTranscript: WhisperModel.allCases.contains {
                FileManager.default.fileExists(atPath: AppFolders.transcripts
                    .appendingPathComponent(TranscriptCache.key(for: url, model: $0.rawValue) + ".json").path)
            }
        )
    }

    /// "Tears of Steel - Blender VFX Open Movie [R6MlUcmOul8]" -> "Tears of Steel - Blender VFX Open Movie"
    static func cleanTitle(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: #"\s*\[[A-Za-z0-9_-]{6,}\]$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "｜", with: "|")
    }

    // MARK: - Covers

    private func thumbnailURL(for url: URL) -> URL {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let raw = "\(url.path)|\(size)"
        let name = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        return AppFolders.thumbnails.appendingPathComponent(name + ".jpg")
    }

    private func loadOrCreateThumbnail(for item: LibraryItem) {
        let file = thumbnailURL(for: item.url)
        if let image = NSImage(contentsOf: file) {
            thumbnails[item.id] = image
            return
        }
        guard thumbnailAttempts.insert(item.id).inserted else { return }
        let url = item.url, isAudio = item.isAudio, id = item.id
        Task {
            let (data, duration) = await Self.makeThumbnail(for: url, isAudio: isAudio, to: file)
            if let duration, records[id]?.duration == nil {
                records[id, default: Record()].duration = duration
                save()
            }
            if data, let image = NSImage(contentsOf: file) {
                thumbnails[id] = image
            }
            if duration != nil { refresh() }
        }
    }

    /// A frame from 10% into the video (or the album art for songs), saved as JPEG.
    /// Falls back to ffmpeg for formats macOS cannot decode (e.g. VP9, .mkv).
    private nonisolated static func makeThumbnail(for url: URL, isAudio: Bool, to file: URL) async -> (Bool, Double?) {
        let asset = AVURLAsset(url: url)
        let seconds = (try? await asset.load(.duration))?.seconds
        let duration = seconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }

        if isAudio {
            let metadata = (try? await asset.load(.commonMetadata)) ?? []
            if let artwork = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first,
               let data = try? await artwork.load(.dataValue) {
                return ((try? data.write(to: file)) != nil, duration)
            }
            return (false, duration)
        }

        let time = min(max((duration ?? 60) * 0.1, 1), 120)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 720)
        if let (image, _) = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)),
           let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            return ((try? jpeg.write(to: file)) != nil, duration)
        }
        let ok = (try? await MediaTools().extractFrame(from: url, at: time, to: file)) != nil
        return (ok, duration)
    }
}
