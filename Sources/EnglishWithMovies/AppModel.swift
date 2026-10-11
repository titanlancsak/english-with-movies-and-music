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

    /// The screens in the sidebar.
    enum Section: Hashable {
        case library, player, savedWords, review, practice
    }

    @Published var section: Section = .library
    @Published private(set) var status: Status = .idle
    @Published private(set) var mediaURL: URL?
    @Published private(set) var hasVideo = false
    @Published private(set) var player: AVPlayer?
    @Published private(set) var transcript: Transcript?
    @Published private(set) var activeLine: Int?
    @Published private(set) var activeWord: Int?
    @Published var followPlayback = true
    /// Incremented when the subtitles must jump to `scrollLine` (after the video jumps).
    @Published private(set) var scrollRequest = 0
    private(set) var scrollLine: Int?
    private var lastObservedTime: Double?
    /// The line being practiced (shows the practice sheet).
    @Published var practiceLine: TranscriptLine?
    @Published var model: WhisperModel {
        didSet { UserDefaults.standard.set(model.rawValue, forKey: "whisperModel") }
    }

    // MARK: Study tools

    /// Playback speed (0.5 to 1.25), kept between films.
    @Published var speed = Float(UserDefaults.standard.object(forKey: "speed") as? Double ?? 1) {
        didSet {
            UserDefaults.standard.set(Double(speed), forKey: "speed")
            applySpeed()
        }
    }
    /// Plays the current line again and again.
    @Published var loopLine = false {
        didSet { loopIndex = loopLine ? activeLine : nil }
    }
    private var loopIndex: Int?
    /// Listening challenge: the subtitles stay hidden until a line is clicked.
    @Published var hideSubtitles = false {
        didSet { revealedLines = [] }
    }
    @Published var revealedLines: Set<Int> = []
    /// Underlines words outside the 5,000 most common ones.
    @Published var highlightUncommon = UserDefaults.standard.object(forKey: "highlightUncommon") as? Bool ?? true {
        didSet { UserDefaults.standard.set(highlightUncommon, forKey: "highlightUncommon") }
    }
    /// Shadowing: listen to a line, repeat it, get the score, go to the next one.
    @Published var shadowing = false
    @Published var showSearch = false
    @Published var searchQuery = "" {
        didSet { searchIndex = 0 }
    }
    @Published private(set) var searchIndex = 0
    /// Where the subtitles came from when they were not transcribed, e.g. "Legenda do YouTube".
    @Published private(set) var subtitleSource: String?

    let library = LibraryStore()
    let study = StudyStore()
    private var positionObserver: Any?

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
    /// Pauses playback at the end of a line played with `playSegment`.
    private var segmentObserver: Any?
    private var segmentCompletion: (() -> Void)?

    /// Name of the open movie or song, used to group practice history.
    var sourceName: String? { mediaURL?.deletingPathExtension().lastPathComponent }

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
        section = .player
        if let time, player != nil, url.standardizedFileURL == mediaURL?.standardizedFileURL {
            seek(to: time)
            player?.play()
            return
        }
        pendingSeek = time
        savePosition()
        cancel()
        tearDownPlayer()
        mediaURL = url
        subtitleSource = nil
        revealedLines = []
        loopLine = false
        searchQuery = ""
        library.recordOpened(url)
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
            let key = TranscriptCache.key(for: mediaURL, model: model.rawValue)
            TranscriptCache.save(transcript!, key: key)
            setSubtitleSource("Legenda importada (.srt)", key: key)
        }
    }

    /// Remembers (next to the cached transcript) that it came from a subtitle file, not from Whisper.
    private func setSubtitleSource(_ source: String?, key: String) {
        subtitleSource = source
        let marker = AppFolders.transcripts.appendingPathComponent(key + ".source")
        if let source {
            try? source.write(to: marker, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: marker)
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

    /// Closes the movie or song and goes back to the library.
    func closeMedia() {
        savePosition()
        cancel()
        tearDownPlayer()
        mediaURL = nil
        transcript = nil
        hasVideo = false
        status = .idle
        section = .library
        library.refresh()
    }

    /// Remembers where playback stopped (called when switching media and when quitting).
    func savePosition() {
        if let mediaURL, let player {
            library.updatePosition(mediaURL, seconds: player.currentTime().seconds,
                                   duration: player.currentItem?.duration.seconds)
        }
        library.save()
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
            subtitleSource = try? String(contentsOf: AppFolders.transcripts.appendingPathComponent(key + ".source"), encoding: .utf8)
            status = .ready
            return
        }
        // Subtitles that came with the video (YouTube, or a .srt next to the film) are ready at once
        // and usually more accurate than a transcription. "Transcrever de novo" uses Whisper instead.
        if !skipCache, let srt = MediaFiles.siblingSubtitles(for: url),
           let contents = (try? String(contentsOf: srt, encoding: .utf8)) ?? (try? String(contentsOf: srt, encoding: .isoLatin1)) {
            let parsed = SRTParser.parse(contents)
            if !parsed.lines.isEmpty {
                TranscriptCache.save(parsed, key: key)
                transcript = parsed
                let fromYouTube = url.deletingLastPathComponent().standardizedFileURL == AppFolders.downloads.standardizedFileURL
                setSubtitleSource(fromYouTube ? "Legenda do YouTube" : "Legenda do arquivo .srt", key: key)
                status = .ready
                return
            }
        }
        setSubtitleSource(nil, key: key)

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
        jumpSubtitles(to: seconds)
    }

    func pause() {
        player?.pause()
    }

    // MARK: - Pronunciation practice

    func practiceCurrentLine() {
        guard let transcript, let index = activeLine ?? (transcript.lines.isEmpty ? nil : 0) else { return }
        pause()
        practiceLine = transcript.lines[index]
    }

    /// Plays only this line, then pauses.
    /// `completion` runs when the line has finished playing (not when it is interrupted).
    func playSegment(_ line: TranscriptLine, then completion: (() -> Void)? = nil) {
        guard let player else { return }
        stopSegment()
        seek(to: line.start)
        let end = CMTime(seconds: line.end + 0.2, preferredTimescale: 600)
        segmentCompletion = completion
        segmentObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: end)], queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                let completion = self?.segmentCompletion
                self?.stopSegment()
                completion?()
            }
        }
        player.play()
    }

    func stopSegment() {
        segmentCompletion = nil
        guard let segmentObserver else { return }
        player?.pause()
        player?.removeTimeObserver(segmentObserver)
        self.segmentObserver = nil
    }

    // MARK: - Shadowing and search

    /// Starts shadowing from the current line: listen, repeat, score, next line.
    func startShadowing() {
        guard transcript != nil else { return }
        loopLine = false
        shadowing = true
        practiceCurrentLine()
    }

    func line(after line: TranscriptLine) -> TranscriptLine? {
        transcript?.lines.first { $0.start > line.start + 0.01 }
    }

    var searchMatches: [Int] { transcript?.lineIndices(matching: searchQuery) ?? [] }

    /// Goes to the next (1) or previous (-1) line containing the search text.
    func showSearchResult(_ step: Int) {
        let matches = searchMatches
        guard !matches.isEmpty, let transcript else { return }
        searchIndex = ((searchIndex + step) % matches.count + matches.count) % matches.count
        seek(to: transcript.lines[matches[searchIndex]].start)
    }

    var currentSearchLine: Int? {
        let matches = searchMatches
        return matches.isEmpty ? nil : matches[min(searchIndex, matches.count - 1)]
    }

    private func applySpeed() {
        guard let player else { return }
        player.defaultRate = speed
        if player.timeControlStatus == .playing { player.rate = speed }
    }

    /// Transcribes a recording of the user and scores it against the line.
    /// The expected sentence is not given to Whisper, so it cannot "guess" it.
    func assess(recording: URL, line: TranscriptLine, phonemes: PhonemeEngine) async throws -> PronunciationResult {
        let modelURL: URL
        if model.isDownloaded {
            modelURL = model.localURL
        } else if let downloaded = WhisperModel.allCases.first(where: \.isDownloaded) {
            modelURL = downloaded.localURL
        } else {
            try await ModelDownloader().download(.base) { _ in }
            modelURL = WhisperModel.base.localURL
        }
        async let heard = MediaTools().transcribe(wav: recording, model: modelURL) { _ in }
        // The sound analysis is a bonus: if it fails, the word-level score still works.
        let sounds = try? await phonemes.analyze(recording: recording, line: line)
        return PronunciationScorer.score(target: line, spoken: try await heard.lines.flatMap(\.words), sounds: sounds)
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
        positionObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let url = self.mediaURL else { return }
                self.library.updatePosition(url, seconds: time.seconds, duration: self.player?.currentItem?.duration.seconds)
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.updateActive(time.seconds) }
        }
        // Slower speeds keep the voice's pitch.
        player.currentItem?.audioTimePitchAlgorithm = .spectral
        player.defaultRate = speed
        // `--preview` (for screenshots): open silent and paused.
        if Self.isPreview {
            player.isMuted = true
        } else {
            player.play()
        }
    }

    static let isPreview = CommandLine.arguments.contains("--preview")

    private func tearDownPlayer() {
        stopSegment()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let positionObserver { player?.removeTimeObserver(positionObserver) }
        timeObserver = nil
        positionObserver = nil
        player?.pause()
        player = nil
        playbackURL = nil
        lastObservedTime = nil
        activeLine = nil
        activeWord = nil
    }

    /// Follows playback again and scrolls the subtitles to the line at `time`.
    private func jumpSubtitles(to time: Double) {
        followPlayback = true
        scrollLine = transcript?.nearestLineIndex(at: time)
        scrollRequest += 1
    }

    /// Only publishes when the highlighted line/word actually changes, to keep the UI light.
    private func updateActive(_ time: Double) {
        // Study time for the daily goal: real seconds of playback.
        if let last = lastObservedTime, player?.timeControlStatus == .playing, time > last, time - last < 1 {
            study.add((time - last) / Double(max(speed, 0.1)))
        }
        guard let transcript else {
            lastObservedTime = time
            return
        }
        // A jump: the slider, the skip buttons, a click on a line... anything but normal playback
        // (the observer runs every 0.05 s, so normal playback moves far less than a second).
        if let last = lastObservedTime, abs(time - last) > 1 {
            jumpSubtitles(to: time)
            if loopLine { loopIndex = transcript.lineIndex(at: time) }
        }
        lastObservedTime = time
        // Repeat the line: back to its start once it ends.
        if loopLine, segmentObserver == nil {
            if loopIndex == nil { loopIndex = transcript.lineIndex(at: time) }
            if let index = loopIndex, time > transcript.lines[index].end + 0.3 {
                seek(to: transcript.lines[index].start)
                return
            }
        }
        let line = transcript.lineIndex(at: time)
        let word = line.flatMap { transcript.lines[$0].wordIndex(at: time) }
        if line != activeLine { activeLine = line }
        if word != activeWord { activeWord = word }
    }
}
