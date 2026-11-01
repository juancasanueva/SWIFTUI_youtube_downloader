import Foundation
import Observation

/// Runs up to `maxParallel` downloads; the rest wait in order.
/// Everything happens on the main actor, so the slot count can't race.
@MainActor
@Observable
final class DownloadQueue {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let video: YouTubeURL
        let destination: URL
        let transcriptLanguages: String?
        var title: String?
        var progress: DownloadProgress?
        var isFetchingTranscripts = false

        fileprivate var transcripts: [URL] = []
        fileprivate var transcriptError: String?
    }

    private(set) var active: [Item] = []
    private(set) var queued: [Item] = []
    private(set) var inputError: String?

    let history: HistoryStore

    private var playlistTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var downloadTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let downloader: any VideoDownloading
    @ObservationIgnored private let maxParallel: Int

    var isReadingPlaylist: Bool {
        !playlistTasks.isEmpty
    }

    var isBusy: Bool {
        !active.isEmpty || !queued.isEmpty || isReadingPlaylist
    }

    init(downloader: any VideoDownloading, history: HistoryStore, maxParallel: Int = 3) {
        self.downloader = downloader
        self.history = history
        self.maxParallel = maxParallel
    }

    // MARK: - Adding

    /// Returns whether the text was accepted, so the caller knows to clear it.
    func submit(urlText: String, destination: URL, transcriptLanguages: String?) -> Bool {
        inputError = nil

        if let video = YouTubeURL(urlText) {
            return add(video, title: nil, destination: destination, transcriptLanguages: transcriptLanguages)
        }
        if let playlist = YouTubePlaylistURL(urlText) {
            readPlaylist(playlist, destination: destination, transcriptLanguages: transcriptLanguages)
            return true
        }
        inputError = "Enter a valid YouTube video or playlist URL."
        return false
    }

    /// The old entry stays until the new result replaces it, so cancelling the retry loses nothing.
    func downloadAgain(_ entry: HistoryEntry, destination: URL, transcriptLanguages: String?) {
        inputError = nil
        guard let video = YouTubeURL(entry.video.absoluteString) else { return }

        _ = add(video, title: entry.title, destination: destination, transcriptLanguages: transcriptLanguages)
    }

    func clearInputError() {
        inputError = nil
    }

    private func add(_ video: YouTubeURL, title: String?, destination: URL, transcriptLanguages: String?) -> Bool {
        guard enqueue(video, title: title, destination: destination, transcriptLanguages: transcriptLanguages) else {
            inputError = "This video is already in the list."
            return false
        }
        startWaitingDownloads()
        return true
    }

    /// Two processes writing the same video would corrupt the file, so a video can only be listed once.
    private func enqueue(_ video: YouTubeURL, title: String?, destination: URL, transcriptLanguages: String?) -> Bool {
        guard !(active + queued).contains(where: { $0.video == video }) else {
            return false
        }
        queued.append(Item(video: video, destination: destination, transcriptLanguages: transcriptLanguages, title: title))
        return true
    }

    private func readPlaylist(_ playlist: YouTubePlaylistURL, destination: URL, transcriptLanguages: String?) {
        let id = UUID()
        playlistTasks[id] = Task {
            let result = await Result { try await downloader.playlistEntries(of: playlist) }
            guard !Task.isCancelled else { return }
            playlistTasks[id] = nil

            switch result {
            case .success(let entries) where entries.isEmpty:
                inputError = "This playlist has no videos."
            case .success(let entries):
                for entry in entries {
                    _ = enqueue(entry.video, title: entry.title, destination: destination, transcriptLanguages: transcriptLanguages)
                }
                startWaitingDownloads()
            case .failure(let error):
                inputError = error.localizedDescription
            }
        }
    }

    // MARK: - Cancelling

    /// Stops a running download, or removes one still waiting.
    func cancel(_ id: Item.ID) {
        queued.removeAll { $0.id == id }
        guard active.contains(where: { $0.id == id }) else { return }

        active.removeAll { $0.id == id }
        downloadTasks.removeValue(forKey: id)?.cancel()
        startWaitingDownloads()
    }

    func clearQueue() {
        queued.removeAll()
    }

    func cancelAll() {
        queued.removeAll()
        active.removeAll()
        downloadTasks.values.forEach { $0.cancel() }
        downloadTasks.removeAll()
        playlistTasks.values.forEach { $0.cancel() }
        playlistTasks.removeAll()
    }

    // MARK: - Running

    private func startWaitingDownloads() {
        while active.count < maxParallel, !queued.isEmpty {
            let item = queued.removeFirst()
            active.append(item)

            let request = DownloadRequest(
                video: item.video,
                destination: item.destination,
                transcriptLanguages: item.transcriptLanguages
            )
            let events = downloader.download(request)
            downloadTasks[item.id] = Task { await consume(events, for: item.id) }
        }
    }

    private func consume(_ events: AsyncThrowingStream<DownloadEvent, Error>, for id: Item.ID) async {
        var file: URL?
        var failure: String?

        do {
            for try await event in events {
                if case .finished(let url) = event { file = url }
                apply(event, to: id)
            }
        } catch {
            failure = error.localizedDescription
        }

        // Gone from the list means it was cancelled, and a cancelled download leaves no record.
        guard let item = active.first(where: { $0.id == id }) else { return }

        active.removeAll { $0.id == id }
        downloadTasks[id] = nil
        record(item, file: file, failure: failure)
        startWaitingDownloads()
    }

    private func apply(_ event: DownloadEvent, to id: Item.ID) {
        guard let index = active.firstIndex(where: { $0.id == id }) else { return }

        switch event {
        case .title(let title): active[index].title = title
        case .progress(let progress): active[index].progress = progress
        case .fetchingTranscripts: active[index].isFetchingTranscripts = true
        case .transcript(let url): active[index].transcripts.append(url)
        case .transcriptsFailed(let message): active[index].transcriptError = message
        case .finished: break
        }
    }

    private func record(_ item: Item, file: URL?, failure: String?) {
        let outcome: HistoryEntry.Outcome
        if let file, failure == nil {
            outcome = .completed(file: file, transcripts: item.transcripts, transcriptError: item.transcriptError)
        } else {
            outcome = .failed(failure ?? "The download ended without a file.")
        }
        history.add(HistoryEntry(video: item.video.url, title: item.title, date: .now, outcome: outcome))
    }
}

private extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do {
            self = .success(try await body())
        } catch {
            self = .failure(error)
        }
    }
}
