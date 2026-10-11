import AVFoundation
import Foundation

/// Records the microphone to a 16 kHz mono WAV (the format Whisper expects) and
/// stops by itself after the user finishes speaking.
@MainActor
final class VoiceRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    /// Input level, 0...1, for the meter.
    @Published private(set) var level: Double = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt = Date()
    private var heardSpeech = false
    private var silenceSince: Date?
    private var maxDuration: TimeInterval = 15
    private var onFinish: ((URL, Bool) -> Void)?

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// - Parameter onFinish: called with the file and whether any speech was detected.
    func start(to url: URL, maxDuration: TimeInterval, onFinish: @escaping (URL, Bool) -> Void) throws {
        stop(notify: false)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw RecorderError.couldNotStart }

        self.recorder = recorder
        self.maxDuration = maxDuration
        self.onFinish = onFinish
        startedAt = Date()
        heardSpeech = false
        silenceSince = nil
        isRecording = true

        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        stop(notify: true)
    }

    private func stop(notify: Bool) {
        timer?.invalidate()
        timer = nil
        guard let recorder else { return }
        recorder.stop()
        self.recorder = nil
        isRecording = false
        level = 0
        let finish = onFinish
        onFinish = nil
        if notify { finish?(recorder.url, heardSpeech) }
    }

    /// Stops automatically: 1.2 s of silence after speaking, nothing said in 6 s, or the time limit.
    private func tick() {
        guard let recorder else { return }
        recorder.updateMeters()
        let power = Double(recorder.averagePower(forChannel: 0))  // dB, -160...0
        level = min(1, max(0, (power + 50) / 50))

        let now = Date()
        let elapsed = now.timeIntervalSince(startedAt)
        if power > -32 {
            heardSpeech = true
            silenceSince = nil
        } else if power < -40, heardSpeech {
            silenceSince = silenceSince ?? now
        }

        let finishedSpeaking = silenceSince.map { now.timeIntervalSince($0) > 1.2 } ?? false
        if finishedSpeaking || (!heardSpeech && elapsed > 6) || elapsed > maxDuration {
            stop()
        }
    }

    enum RecorderError: LocalizedError {
        case couldNotStart
        var errorDescription: String? { "Não foi possível usar o microfone." }
    }
}
