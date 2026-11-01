import Foundation
import Observation
import OSLog

nonisolated struct HistoryEntry: Identifiable, Equatable, Codable {
    enum Outcome: Equatable, Codable {
        case completed(file: URL, transcripts: [URL], transcriptError: String?)
        case failed(String)
    }

    var id = UUID()
    let video: URL
    let title: String?
    let date: Date
    let outcome: Outcome
}

/// Past downloads, newest first, kept in a JSON file. Each video appears once.
@MainActor
@Observable
final class HistoryStore {
    private static let maxEntries = 200
    private static let logger = Logger(subsystem: "com.juancasanueva.youtubedownload", category: "History")

    private(set) var entries: [HistoryEntry] = []

    @ObservationIgnored private let fileURL: URL

    nonisolated static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "com.juancasanueva.youtubedownload", directoryHint: .isDirectory)
            .appending(path: "history.json")
    }

    init(fileURL: URL = HistoryStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    func add(_ entry: HistoryEntry) {
        entries.removeAll { $0.video == entry.video }
        entries.insert(entry, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        save()
    }

    func remove(_ id: HistoryEntry.ID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    /// History is a convenience, so a missing or damaged file just means starting empty.
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
        } catch {
            Self.logger.error("Ignoring unreadable history: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Could not save history: \(error.localizedDescription)")
        }
    }
}
