import Foundation
import LinguaCore

/// Sound-by-sound pronunciation analysis.
///
/// - Expected sounds: espeak-ng converts each word of the sentence into phonemes.
/// - Heard sounds: a phoneme recognizer (wav2vec2, converted to ONNX) runs in a Python worker
///   that stays open, so the model is loaded only once.
@MainActor
final class PhonemeEngine: ObservableObject {
    enum State: Equatable {
        case notInstalled
        case installing(Double, String)
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .notInstalled

    static let folder = AppFolders.root.appendingPathComponent("phonemes", isDirectory: true)
    private var worker: PhonemeWorker?
    private var vocabulary: Set<String> = []

    init() {
        state = Self.isInstalled ? .ready : .notInstalled
    }

    static var isInstalled: Bool {
        ["model.onnx", "vocab.json", "worker.py", "venv/bin/python"].allSatisfy {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
    }

    /// The setup scripts: inside the .app, or next to the sources when run with `swift run`.
    private static var scriptsFolder: URL {
        if let bundled = Bundle.main.url(forResource: "Phonemes", withExtension: nil) { return bundled }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Phonemes")
    }

    // MARK: - Installation

    func install() {
        guard MediaTools.locate("espeak-ng") != nil else {
            state = .failed("Instale o espeak-ng antes: brew install espeak-ng")
            return
        }
        state = .installing(0, "Começando…")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [Self.scriptsFolder.appendingPathComponent("setup.sh").path, Self.folder.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let log = LineCollector()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            for line in log.append(text) {
                let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
                guard parts.count == 3, parts[0] == "PROGRESS", let value = Double(parts[1]) else { continue }
                Task { @MainActor in self?.state = .installing(value / 100, parts[2]) }
            }
        }
        process.terminationHandler = { [weak self] process in
            pipe.fileHandleForReading.readabilityHandler = nil
            let ok = process.terminationStatus == 0
            let output = log.text
            Task { @MainActor in
                if ok, Self.isInstalled {
                    self?.state = .ready
                } else {
                    let error = output.split(separator: "\n").last { $0.hasPrefix("ERROR") }.map(String.init)
                    self?.state = .failed(error ?? "A instalação falhou:\n" + String(output.suffix(500)))
                }
            }
        }
        do {
            try process.run()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Removes the model and its Python environment (about 500 MB).
    func uninstall() {
        worker?.stop()
        worker = nil
        try? FileManager.default.removeItem(at: Self.folder)
        state = .notInstalled
    }

    // MARK: - Analysis

    /// Compares the recording with the line, sound by sound. Returns nil when not installed.
    func analyze(recording: URL, line: TranscriptLine) async throws -> SoundAnalysis? {
        guard state == .ready else { return nil }
        let words = line.words.map(\.text).filter { $0.contains(where: \.isLetter) }
        guard !words.isEmpty else { return nil }

        if worker == nil {
            worker = try PhonemeWorker(folder: Self.folder)
            if let data = try? Data(contentsOf: Self.folder.appendingPathComponent("vocab.json")),
               let vocab = try? JSONDecoder().decode([String: Int].self, from: data) {
                vocabulary = Set(vocab.keys)
            }
        }
        async let heard = worker!.phonemes(for: recording)
        let expected = try await Self.expectedPhonemes(for: words, vocabulary: vocabulary)
        return PhonemeAnalyzer.analyze(words: words, expected: expected, heard: try await heard)
    }

    /// One espeak-ng call per word keeps each word's sounds separate.
    private static func expectedPhonemes(for words: [String], vocabulary: Set<String>) async throws -> [[String]] {
        guard let espeak = MediaTools.locate("espeak-ng") else {
            throw PhonemeError.message("Instale o espeak-ng: brew install espeak-ng")
        }
        return try await Task.detached {
            try words.map { word in
                let process = Process()
                process.executableURL = espeak
                process.arguments = ["-q", "-v", "en-us", "--ipa", "--sep=_", word]
                let pipe = Pipe()
                process.standardOutput = pipe
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return PhonemeAnalyzer.phonemes(fromEspeak: String(decoding: data, as: UTF8.self), vocabulary: vocabulary)
            }
        }.value
    }

    enum PhonemeError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case .message(let text) = self { return text }
            return nil
        }
    }
}

/// The Python process running the phoneme model; requests are answered one at a time.
actor PhonemeWorker {
    private let process = Process()
    private let input: FileHandle
    private let output: LineReader

    init(folder: URL) throws {
        process.executableURL = folder.appendingPathComponent("venv/bin/python")
        process.arguments = [folder.appendingPathComponent("worker.py").path, folder.path]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        input = stdin.fileHandleForWriting
        output = LineReader(stdout.fileHandleForReading)
    }

    private var isReady = false

    func phonemes(for wav: URL) async throws -> [String] {
        if !isReady {
            // The first line says the model finished loading.
            guard await output.nextLine() != nil else {
                throw PhonemeEngine.PhonemeError.message("O analisador de sons não abriu.")
            }
            isReady = true
        }
        try input.write(contentsOf: Data((wav.path + "\n").utf8))
        guard let line = await output.nextLine(),
              let response = try? JSONDecoder().decode(Response.self, from: Data(line.utf8)) else {
            throw PhonemeEngine.PhonemeError.message("O analisador de sons parou de responder.")
        }
        if let error = response.error { throw PhonemeEngine.PhonemeError.message(error) }
        return response.phonemes ?? []
    }

    nonisolated func stop() {
        process.terminate()
    }

    private struct Response: Decodable {
        let phonemes: [String]?
        let error: String?
    }
}

/// Delivers a process's output one line at a time to async callers.
private final class LineReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var lines: [String] = []
    private var waiting: [CheckedContinuation<String?, Never>] = []
    private var closed = false

    init(_ handle: FileHandle) {
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                self?.close()
            } else {
                self?.feed(String(decoding: data, as: UTF8.self))
            }
        }
    }

    func nextLine() async -> String? {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if !lines.isEmpty {
                    continuation.resume(returning: lines.removeFirst())
                } else if closed {
                    continuation.resume(returning: nil)
                } else {
                    waiting.append(continuation)
                }
            }
        }
    }

    private func feed(_ text: String) {
        lock.withLock {
            buffer += text
            var parts = buffer.components(separatedBy: "\n")
            buffer = parts.removeLast()
            for line in parts where !line.isEmpty {
                if waiting.isEmpty { lines.append(line) } else { waiting.removeFirst().resume(returning: line) }
            }
        }
    }

    private func close() {
        lock.withLock {
            closed = true
            waiting.forEach { $0.resume(returning: nil) }
            waiting.removeAll()
        }
    }
}

/// Splits streamed output into complete lines.
private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var all = ""

    func append(_ text: String) -> [String] {
        lock.withLock {
            all += text
            buffer += text
            var lines = buffer.components(separatedBy: "\n")
            buffer = lines.removeLast()
            return lines
        }
    }

    var text: String { lock.withLock { all } }
}
