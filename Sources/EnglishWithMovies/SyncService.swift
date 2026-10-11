import Combine
import Foundation
import LinguaCore

/// Keeps saved words, pronunciation history and study time in a file inside a folder the user
/// chooses, typically synced by Google Drive, Dropbox, OneDrive or iCloud Drive. Every device
/// (Mac, Windows, Android) merges that file with its own data, so they all end up the same.
@MainActor
final class SyncService: ObservableObject {
    @Published private(set) var folder: URL?
    @Published private(set) var status = ""

    private let savedWords: SavedWordsStore
    private let practice: PracticeStore
    private let study: StudyStore
    private var subscriptions: Set<AnyCancellable> = []
    private var timer: Timer?

    init(savedWords: SavedWordsStore, practice: PracticeStore, study: StudyStore) {
        self.savedWords = savedWords
        self.practice = practice
        self.study = study
        folder = UserDefaults.standard.string(forKey: "syncFolder").map { URL(fileURLWithPath: $0, isDirectory: true) }

        // Sync a few seconds after a change, and every two minutes for the other devices' changes.
        savedWords.objectWillChange.merge(with: practice.objectWillChange)
            .debounce(for: .seconds(4), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.syncNow() }
            .store(in: &subscriptions)
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNow() }
        }
        syncNow()
    }

    var file: URL? { folder?.appendingPathComponent(SyncDocument.fileName) }

    func setFolder(_ url: URL?) {
        folder = url
        UserDefaults.standard.set(url?.path, forKey: "syncFolder")
        status = ""
        syncNow()
    }

    func syncNow() {
        guard let file else { return }
        var words = savedWords.list
        var history = practice.history
        study.persist()
        var log = study.log
        do {
            let existing = try? Data(contentsOf: file)
            if let existing {
                let remote = try JSONDecoder().decode(SyncDocument.self, from: existing)
                SyncDocument.merge(remote, into: &words, practice: &history, study: &log)
                savedWords.replace(with: words)
                practice.replace(with: history)
                study.replace(with: log)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(SyncDocument(words: words, practice: history, study: log))
            if data != existing { try data.write(to: file, options: .atomic) }
            status = "Sincronizado às " + Date().formatted(date: .omitted, time: .shortened)
        } catch {
            status = "Não foi possível sincronizar: \(error.localizedDescription)"
        }
    }
}
