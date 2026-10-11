import Foundation
import LinguaCore

/// Study time for the daily goal and the streak (~/Library/Application Support/EnglishWithMovies/study.json).
@MainActor
final class StudyStore: ObservableObject {
    @Published private(set) var log: StudyLog
    /// Identifies this computer in the sync file, so its time adds up with the phone's.
    let deviceID: String

    private let fileURL = AppFolders.root.appendingPathComponent("study.json")
    /// Time not yet added to `log`: publishing every 0.05 s of playback would redraw too much.
    private var pending: Double = 0

    init() {
        log = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(StudyLog.self, from: $0) } ?? StudyLog()
        if let saved = UserDefaults.standard.string(forKey: "deviceID") {
            deviceID = saved
        } else {
            deviceID = "mac-" + UUID().uuidString.prefix(8).lowercased()
            UserDefaults.standard.set(deviceID, forKey: "deviceID")
        }
    }

    var goalMinutes: Int {
        get { log.goalMinutes }
        set {
            log.goalMinutes = newValue
            persist()
        }
    }

    var todayMinutes: Int { Int(log.seconds(on: Date()) / 60) }

    /// Adds study time; published and saved every 15 seconds of study (and when the app quits).
    func add(_ seconds: Double) {
        pending += seconds
        if pending >= 15 { persist() }
    }

    func replace(with log: StudyLog) {
        flush()
        guard log != self.log else { return }
        self.log = log
        persist()
    }

    private func flush() {
        guard pending > 0 else { return }
        log.add(pending, device: deviceID)
        pending = 0
    }

    func persist() {
        flush()
        if let data = try? JSONEncoder().encode(log) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
