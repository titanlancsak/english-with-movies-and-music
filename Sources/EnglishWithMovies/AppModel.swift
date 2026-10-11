import AVFoundation
import Foundation
import LinguaCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case working(String, progress: Double?)
        case ready
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var mediaURL: URL?
    @Published private(set) var hasVideo = false
    @Published private(set) var player: AVPlayer?
    @Published private(set) var transcript: Transcript?
    @Published private(set) var activeLine: Int?
    @Published private(set) var activeWord: Int?
    @Published var followPlayback = true
    @Published var model: WhisperModel {
        didSet { UserDefaults.standard.set(model.rawValue, forKey: "whisperModel") }
    }

    let dictionary = DictionaryService(offlineLookup: { word in
        SystemDictionary.define(word).flatMap { SystemDictionaryParser.parse($0, fallbackWord: word) }
    })

    private var tools: MediaTools?
    private var job: Task<Void, Never>?
    private var timeObserver: Any?
    /// The file the player is using: the original, or a converted copy in the work folder.
    private var playbackURL: URL?
    /// Where to start playing once the player is ready.
    private var pendingSeek: Double?

    init() {
        let saved = UserDefaults.standard.string(forKey: "whisperModel")
        model = saved.flatMap(WhisperModel.init(rawValue:)) ?? .base
    }

    // MARK: - Opening files

    /// Opens a movie or song. `time` jumps to that moment (used by saved words).
    func open(_ url: URL, at time: Double? = nil) {
        if url.pathExtension.lowercased() == "srt" {
            importSubtitles(url)
            return
        }
        if let time, player != nil, url.standardizedFileURL == mediaURL?.standardizedFileURL {
            seek(to: time)
            player?.play()
            return
        }
        pendingSeek = time
        cancel()
        tearDownPlayer()
        mediaURL = url
        transcript = nil
        job = Task { await load(url, transcribe: true) }
    }

    /// Downloads a video from a YouTube link, then opens and transcribes it.
    func download(from link: String) {
        let link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { return }
        cancel()
        job = Task {
            let tools = MediaTools()
            self.tools = tools
            status = .working("Baixando o vídeo…", progress: 0)
            do {
                let file = try await tools.downloadVideo(from: link, to: AppFolders.downloads) { value in
                    Task { @MainActor in self.updateProgress(value) }
                }
                try Task.checkCancellation()
                open(file)
            } catch {
                report(error)
            }
        }
    }

    /// Uses an existing .srt instead of transcribing (instant, and exact text if the subtitle is good).
    func importSubtitles(_ url: URL) {
        guard let contents = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else {
            status = .failed("Não consegui ler a legenda.")
            return
        }
        cancel()
        transcript = SRTParser.parse(contents)
        status = mediaURL == nil ? .idle : .ready
        if let mediaURL {
            TranscriptCache.save(transcript!, key: TranscriptCache.key(for: mediaURL, model: model.rawValue))
        }
    }

    /// Re-runs the transcription (e.g. after choosing a more precise model).
    func retranscribe() {
        guard let url = mediaURL else { return }
        cancel()
        transcript = nil
        job = Task { await transcribe(url, skipCache: true) }
    }

    // MARK: - Converted copies

    var isBusy: Bool {
        if case .working = status { return true }
        return false
    }

    /// Converted copies that can be deleted (everything in the work folder except what is playing).
    private func removableCopies() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: AppFolders.work, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.filter { $0.standardizedFileURL != playbackURL?.standardizedFileURL }
    }

    /// Total size in bytes of the copies `clearConvertedCopies()` would delete.
    func convertedCopiesSize() -> Int64 {
        removableCopies().reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// Deletes converted copies. Originals and transcripts are kept; a copy is
    /// recreated automatically the next time its original is opened.
    func clearConvertedCopies() {
        guard !isBusy else { return }
        removableCopies().forEach { try? FileManager.default.removeItem(at: $0) }
    }

    func cancel() {
        tools?.cancel()
        job?.cancel()
        job = nil
        if case .working = status { status = transcript == nil ? .idle : .ready }
    }

    private func load(_ url: URL, transcribe shouldTranscribe: Bool) async {
        do {
            var playableURL = url
            let asset = AVURLAsset(url: url)
            let playable = (try? await asset.load(.isPlayable)) ?? false
            // e.g. VP9/AV1 video: the file opens, but only the sound plays.
            var videoDecodable = true
            for track in (try? await asset.loadTracks(withMediaType: .video)) ?? [] {
                if !((try? await track.load(.isDecodable)) ?? true) { videoDecodable = false }
            }
            if !playable || !videoDecodable {
                status = .working("Convertendo o arquivo para um formato compatível…", progress: nil)
                let output = AppFolders.work.appendingPathComponent(
                    TranscriptCache.key(for: url, model: "convert") + ".mp4")
                if !FileManager.default.fileExists(atPath: output.path) {
                    let tools = MediaTools()
                    self.tools = tools
                    let partial = output.deletingPathExtension().appendingPathExtension("partial.mp4")
                    try await tools.convertToMP4(url, to: partial, transcodeVideo: !videoDecodable)
                    try FileManager.default.moveItem(at: partial, to: output)
                }
                playableURL = output
            }
            let videoTracks = (try? await AVURLAsset(url: playableURL).loadTracks(withMediaType: .video)) ?? []
            hasVideo = !videoTracks.isEmpty
            playbackURL = playableURL
            setUpPlayer(AVPlayer(url: playableURL))
        } catch {
            report(error)
            return
        }
        if shouldTranscribe { await transcribe(url, skipCache: false) }
    }

    private func transcribe(_ url: URL, skipCache: Bool) async {
        let key = TranscriptCache.key(for: url, model: model.rawValue)
        if !skipCache, let cached = TranscriptCache.load(key: key) {
            transcript = cached
            status = .ready
            return
        }

        let tools = MediaTools()
        self.tools = tools
        let wav = AppFolders.work.appendingPathComponent("\(key).wav")
        defer {
            try? FileManager.default.removeItem(at: wav)
            try? FileManager.default.removeItem(at: wav.deletingPathExtension().appendingPathExtension("json"))
        }

        do {
            if !model.isDownloaded {
                status = .working("Baixando o modelo de transcrição (só na primeira vez)…", progress: 0)
                try await ModelDownloader().download(model) { value in
                    Task { @MainActor in self.updateProgress(value) }
                }
            }
            try Task.checkCancellation()

            status = .working("Extraindo o áudio…", progress: nil)
            try await tools.extractAudio(from: url, to: wav)

            status = .working("Transcrevendo as falas…", progress: 0)
            let result = try await tools.transcribe(wav: wav, model: model.localURL) { value in
                Task { @MainActor in self.updateProgress(value) }
            }
            try Task.checkCancellation()

            TranscriptCache.save(result, key: key)
            transcript = result
            status = .ready
        } catch {
            report(error)
        }
    }

    private func updateProgress(_ value: Double) {
        if case .working(let message, _) = status {
            status = .working(message, progress: value)
        }
    }

    private func report(_ error: Error) {
        if error is CancellationError { return }
        if case MediaToolError.cancelled = error { return }
        status = .failed(error.localizedDescription)
    }

    // MARK: - Playback

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        followPlayback = true
    }

    func pause() {
        player?.pause()
    }

    func togglePlay() {
        guard let player else { return }
        player.timeControlStatus == .playing ? player.pause() : player.play()
    }

    private func setUpPlayer(_ player: AVPlayer) {
        self.player = player
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        if let pendingSeek {
            player.seek(to: CMTime(seconds: pendingSeek, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            self.pendingSeek = nil
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.updateActive(time.seconds) }
        }
        player.play()
    }

    private func tearDownPlayer() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.pause()
        player = nil
        playbackURL = nil
        activeLine = nil
        activeWord = nil
    }

    /// Only publishes when the highlighted line/word actually changes, to keep the UI light.
    private func updateActive(_ time: Double) {
        guard let transcript else { return }
        let line = transcript.lineIndex(at: time)
        let word = line.flatMap { transcript.lines[$0].wordIndex(at: time) }
        if line != activeLine { activeLine = line }
        if word != activeWord { activeWord = word }
    }
}
