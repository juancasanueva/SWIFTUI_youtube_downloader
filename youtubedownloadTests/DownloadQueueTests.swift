import Foundation
import Testing
@testable import youtubedownload

/// Each download stays open until the test finishes or fails it.
private final class FakeDownloader: VideoDownloading, @unchecked Sendable {
    private(set) var requests: [DownloadRequest] = []
    private var continuations: [String: AsyncThrowingStream<DownloadEvent, Error>.Continuation] = [:]
    var playlistResult: Result<[PlaylistEntry], Error> = .success([])
    private let cancelledLock = NSLock()
    private var cancelledStorage: [String] = []

    /// Filled from whichever thread ends each stream.
    var cancelled: [String] {
        cancelledLock.withLock { cancelledStorage }
    }

    func download(_ request: DownloadRequest) -> AsyncThrowingStream<DownloadEvent, Error> {
        requests.append(request)
        let key = request.video.url.absoluteString
        let (stream, continuation) = AsyncThrowingStream<DownloadEvent, Error>.makeStream()
        continuation.onTermination = { [weak self] reason in
            guard case .cancelled = reason, let self else { return }
            cancelledLock.withLock { self.cancelledStorage.append(key) }
        }
        continuations[key] = continuation
        return stream
    }

    func playlistEntries(of playlist: YouTubePlaylistURL) async throws -> [PlaylistEntry] {
        try playlistResult.get()
    }

    func yield(_ event: DownloadEvent, for video: String) {
        continuations[Self.canonical(video)]?.yield(event)
    }

    func finish(_ video: String, file: URL) {
        yield(.finished(file), for: video)
        continuations[Self.canonical(video)]?.finish()
    }

    func fail(_ video: String, message: String) {
        continuations[Self.canonical(video)]?.finish(throwing: DownloadError.failed(message))
    }

    var startedVideos: [String] {
        requests.map(\.video.url.absoluteString)
    }

    static func canonical(_ video: String) -> String {
        "https://www.youtube.com/watch?v=\(video)"
    }
}

@MainActor
struct DownloadQueueTests {
    private let destination = URL(filePath: "/tmp/videos", directoryHint: .isDirectory)
    private let file = URL(filePath: "/tmp/videos/clip.mp4")
    private let downloader = FakeDownloader()
    private let history: HistoryStore
    private let queue: DownloadQueue

    init() {
        let historyFile = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/history.json")
        history = HistoryStore(fileURL: historyFile)
        queue = DownloadQueue(downloader: downloader, history: history)
    }

    private func submit(_ text: String, languages: String? = nil) -> Bool {
        queue.submit(urlText: text, destination: destination, transcriptLanguages: languages)
    }

    private func submitVideos(_ ids: String...) {
        for id in ids { _ = submit("https://youtu.be/\(id)") }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Slots

    @Test("Runs at most three downloads and queues the rest in order")
    func limitsParallelDownloads() {
        submitVideos("a", "b", "c", "d", "e")

        #expect(queue.active.map(\.video) == [YouTubeURL("youtu.be/a"), YouTubeURL("youtu.be/b"), YouTubeURL("youtu.be/c")])
        #expect(queue.queued.map(\.video) == [YouTubeURL("youtu.be/d"), YouTubeURL("youtu.be/e")])
        #expect(downloader.requests.count == 3)
    }

    @Test("A finished download frees its slot for the next in the queue")
    func startsNextWhenOneFinishes() async {
        submitVideos("a", "b", "c", "d")

        downloader.finish("a", file: file)
        await waitUntil { downloader.requests.count == 4 }

        #expect(downloader.startedVideos.last == FakeDownloader.canonical("d"))
        #expect(queue.active.count == 3)
        #expect(queue.queued.isEmpty)
    }

    @Test("A failed download also frees its slot")
    func startsNextWhenOneFails() async {
        submitVideos("a", "b", "c", "d")

        downloader.fail("a", message: "Gone")
        await waitUntil { downloader.requests.count == 4 }

        #expect(downloader.startedVideos.last == FakeDownloader.canonical("d"))
    }

    @Test("Passes the folder and transcript languages chosen when it was added")
    func passesRequestDetails() throws {
        _ = submit("https://youtu.be/a", languages: "en,es")

        let request = try #require(downloader.requests.first)
        #expect(request.destination == destination)
        #expect(request.transcriptLanguages == "en,es")
    }

    @Test("Refuses a video that is already running or queued")
    func refusesDuplicates() {
        submitVideos("a", "b", "c", "d")

        #expect(!submit("https://www.youtube.com/watch?v=a"))
        #expect(queue.inputError == "This video is already in the list.")
        #expect(!submit("https://youtu.be/d"))
        #expect(queue.active.count == 3)
        #expect(queue.queued.count == 1)
    }

    @Test("Rejects invalid input without starting anything")
    func rejectsInvalidInput() {
        #expect(!submit("https://example.com"))
        #expect(queue.inputError == "Enter a valid YouTube video or playlist URL.")
        #expect(downloader.requests.isEmpty)
    }

    @Test("A valid submission clears the previous error")
    func clearsErrorOnSuccess() {
        _ = submit("nope")

        #expect(submit("https://youtu.be/a"))
        #expect(queue.inputError == nil)
    }

    // MARK: - Progress

    @Test("Shows each download's own title and progress")
    func tracksProgressPerItem() async {
        submitVideos("a", "b")
        let progress = DownloadProgress(fraction: 0.5, speed: "1MiB/s", timeRemaining: "00:10")

        downloader.yield(.title("Clip A"), for: "a")
        downloader.yield(.progress(progress), for: "a")
        await waitUntil { queue.active.first?.progress == progress }

        #expect(queue.active[0].title == "Clip A")
        #expect(queue.active[0].progress == progress)
        #expect(queue.active[1].title == nil)
        #expect(queue.active[1].progress == nil)
    }

    @Test("Reports the transcript stage")
    func tracksTranscriptStage() async {
        submitVideos("a")

        downloader.yield(.fetchingTranscripts, for: "a")
        await waitUntil { queue.active.first?.isFetchingTranscripts == true }

        #expect(queue.active.first?.isFetchingTranscripts == true)
    }

    // MARK: - Cancelling

    @Test("Cancelling frees the slot at once, stops the download, and records nothing")
    func cancelsActive() async throws {
        submitVideos("a", "b", "c", "d")
        let item = try #require(queue.active.first)

        queue.cancel(item.id)

        #expect(queue.active.count == 3)
        #expect(!queue.active.contains { $0.id == item.id })
        #expect(queue.queued.isEmpty)
        await waitUntil { downloader.cancelled.contains(FakeDownloader.canonical("a")) }
        #expect(downloader.cancelled == [FakeDownloader.canonical("a")])
        #expect(history.entries.isEmpty)
    }

    @Test("A cancelled video can be added again")
    func allowsAddingAfterCancel() throws {
        submitVideos("a")
        queue.cancel(try #require(queue.active.first).id)

        #expect(submit("https://youtu.be/a"))
    }

    @Test("Removing a queued item never starts it")
    func removesQueued() async throws {
        submitVideos("a", "b", "c", "d", "e")

        queue.cancel(try #require(queue.queued.first).id)
        downloader.finish("a", file: file)
        await waitUntil { downloader.requests.count == 4 }

        #expect(downloader.startedVideos.last == FakeDownloader.canonical("e"))
    }

    @Test("Clearing the queue leaves running downloads alone")
    func clearsQueue() {
        submitVideos("a", "b", "c", "d", "e")

        queue.clearQueue()

        #expect(queue.queued.isEmpty)
        #expect(queue.active.count == 3)
    }

    @Test("Cancelling everything empties both lists and stops every download")
    func cancelsAll() async {
        submitVideos("a", "b", "c", "d")

        queue.cancelAll()

        #expect(queue.active.isEmpty)
        #expect(queue.queued.isEmpty)
        #expect(downloader.requests.count == 3)
        await waitUntil { downloader.cancelled.count == 3 }
        #expect(downloader.cancelled.count == 3)
    }

    // MARK: - History

    @Test("Records a completed download with its title and transcripts")
    func recordsCompletion() async throws {
        let transcript = URL(filePath: "/tmp/videos/clip.en.vtt")
        submitVideos("a")

        downloader.yield(.title("Clip"), for: "a")
        downloader.yield(.transcript(transcript), for: "a")
        downloader.finish("a", file: file)
        await waitUntil { queue.active.isEmpty }

        let entry = try #require(history.entries.first)
        #expect(entry.title == "Clip")
        #expect(entry.video == YouTubeURL("youtu.be/a")?.url)
        #expect(entry.outcome == .completed(file: file, transcripts: [transcript], transcriptError: nil))
    }

    @Test("Records a transcript failure alongside the finished video")
    func recordsTranscriptFailure() async throws {
        submitVideos("a")

        downloader.yield(.transcriptsFailed("HTTP Error 429"), for: "a")
        downloader.finish("a", file: file)
        await waitUntil { queue.active.isEmpty }

        let entry = try #require(history.entries.first)
        #expect(entry.outcome == .completed(file: file, transcripts: [], transcriptError: "HTTP Error 429"))
    }

    @Test("Records a failed download with its message")
    func recordsFailure() async throws {
        submitVideos("a")

        downloader.fail("a", message: "This video is unavailable")
        await waitUntil { queue.active.isEmpty }

        let entry = try #require(history.entries.first)
        #expect(entry.outcome == .failed("This video is unavailable"))
    }

    @Test("Downloading again keeps the old entry until the new result replaces it")
    func retriesFromHistory() async throws {
        submitVideos("a")
        downloader.fail("a", message: "Gone")
        await waitUntil { queue.active.isEmpty }
        let entry = try #require(history.entries.first)

        queue.downloadAgain(entry, destination: destination, transcriptLanguages: nil)

        #expect(history.entries == [entry])
        #expect(queue.active.map(\.video.url) == [entry.video])
        #expect(downloader.requests.count == 2)

        downloader.finish("a", file: file)
        await waitUntil { queue.active.isEmpty }

        #expect(history.entries.count == 1)
        #expect(history.entries.first?.outcome == .completed(file: file, transcripts: [], transcriptError: nil))
    }

    @Test("Cancelling a retry keeps the old history entry")
    func cancellingRetryKeepsEntry() async throws {
        submitVideos("a")
        downloader.fail("a", message: "Gone")
        await waitUntil { queue.active.isEmpty }
        let entry = try #require(history.entries.first)

        queue.downloadAgain(entry, destination: destination, transcriptLanguages: nil)
        queue.cancel(try #require(queue.active.first).id)

        #expect(history.entries == [entry])
    }

    @Test("Downloading again while that video is already running says so and keeps the entry")
    func retryWhileRunningIsRefused() async throws {
        submitVideos("a")
        downloader.fail("a", message: "Gone")
        await waitUntil { queue.active.isEmpty }
        let entry = try #require(history.entries.first)
        submitVideos("a")

        queue.downloadAgain(entry, destination: destination, transcriptLanguages: nil)

        #expect(queue.inputError == "This video is already in the list.")
        #expect(queue.active.count == 1)
        #expect(history.entries == [entry])
    }

    @Test("Downloading again keeps the known title")
    func retryKeepsTitle() async throws {
        submitVideos("a")
        downloader.yield(.title("Clip"), for: "a")
        await waitUntil { queue.active.first?.title == "Clip" }
        downloader.fail("a", message: "Gone")
        await waitUntil { queue.active.isEmpty }

        queue.downloadAgain(try #require(history.entries.first), destination: destination, transcriptLanguages: nil)

        #expect(queue.active.first?.title == "Clip")
    }

    // MARK: - Playlists

    private let playlistURL = "https://www.youtube.com/playlist?list=PL1"

    private func entries(_ ids: String...) -> [PlaylistEntry] {
        ids.map { PlaylistEntry(video: YouTubeURL("youtu.be/\($0)")!, title: "Title \($0)") }
    }

    @Test("A playlist's videos go through the same three slots, with their titles")
    func expandsPlaylist() async {
        downloader.playlistResult = .success(entries("a", "b", "c", "d", "e"))

        #expect(submit(playlistURL))
        #expect(queue.isReadingPlaylist)
        await waitUntil { queue.active.count == 3 }

        #expect(!queue.isReadingPlaylist)
        #expect(queue.active.map(\.title) == ["Title a", "Title b", "Title c"])
        #expect(queue.queued.map(\.title) == ["Title d", "Title e"])
    }

    @Test("A playlist skips videos already running")
    func playlistSkipsDuplicates() async {
        submitVideos("a")
        downloader.playlistResult = .success(entries("a", "b"))

        _ = submit(playlistURL)
        await waitUntil { queue.active.count == 2 }

        #expect(downloader.startedVideos == [FakeDownloader.canonical("a"), FakeDownloader.canonical("b")])
        #expect(queue.inputError == nil)
    }

    @Test("Shows why a playlist could not be read")
    func reportsPlaylistFailure() async {
        downloader.playlistResult = .failure(DownloadError.failed("The playlist does not exist"))

        _ = submit(playlistURL)
        await waitUntil { !queue.isReadingPlaylist }

        #expect(queue.inputError == "The playlist does not exist")
        #expect(queue.active.isEmpty)
    }

    @Test("Says so when a playlist has no videos")
    func reportsEmptyPlaylist() async {
        _ = submit(playlistURL)
        await waitUntil { !queue.isReadingPlaylist }

        #expect(queue.inputError == "This playlist has no videos.")
    }

    @Test("Cancelling everything also drops a playlist still being read")
    func cancelAllDropsPendingPlaylist() async {
        downloader.playlistResult = .success(entries("a"))

        _ = submit(playlistURL)
        queue.cancelAll()
        for _ in 0..<200 { await Task.yield() }

        #expect(queue.active.isEmpty)
        #expect(!queue.isReadingPlaylist)
        #expect(downloader.requests.isEmpty)
    }
}

@MainActor
struct HistoryStoreTests {
    private func makeFileURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/nested/history.json")
    }

    private func entry(_ id: String, outcome: HistoryEntry.Outcome = .failed("Gone")) -> HistoryEntry {
        HistoryEntry(video: YouTubeURL("youtu.be/\(id)")!.url, title: id, date: Date(timeIntervalSince1970: 1000), outcome: outcome)
    }

    @Test("Keeps entries across launches, newest first, with every outcome intact")
    func persists() {
        let url = makeFileURL()
        let file = URL(filePath: "/tmp/My Videos/clip.mp4")
        let completed = entry("a", outcome: .completed(file: file, transcripts: [URL(filePath: "/tmp/clip.en.vtt")], transcriptError: "429"))
        let store = HistoryStore(fileURL: url)

        store.add(completed)
        store.add(entry("b"))

        let reloaded = HistoryStore(fileURL: url)
        #expect(reloaded.entries.map(\.title) == ["b", "a"])
        #expect(reloaded.entries.last == completed)
    }

    @Test("Downloading the same video again keeps one entry, at the top")
    func replacesSameVideo() {
        let store = HistoryStore(fileURL: makeFileURL())

        store.add(entry("a"))
        store.add(entry("b"))
        store.add(entry("a", outcome: .failed("Again")))

        #expect(store.entries.map(\.title) == ["a", "b"])
        #expect(store.entries.first?.outcome == .failed("Again"))
    }

    @Test("Keeps only the latest 200 entries")
    func capsEntries() {
        let store = HistoryStore(fileURL: makeFileURL())

        for index in 0..<205 { store.add(entry("v\(index)")) }

        #expect(store.entries.count == 200)
        #expect(store.entries.first?.title == "v204")
        #expect(store.entries.last?.title == "v5")
    }

    @Test("Removing and clearing also persist")
    func removesAndClears() throws {
        let url = makeFileURL()
        let store = HistoryStore(fileURL: url)
        store.add(entry("a"))
        store.add(entry("b"))

        store.remove(try #require(store.entries.first).id)
        #expect(HistoryStore(fileURL: url).entries.map(\.title) == ["a"])

        store.clear()
        #expect(HistoryStore(fileURL: url).entries.isEmpty)
    }

    @Test("Starts empty when the file is missing or unreadable")
    func survivesBadFile() throws {
        #expect(HistoryStore(fileURL: makeFileURL()).entries.isEmpty)

        let url = makeFileURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        #expect(HistoryStore(fileURL: url).entries.isEmpty)
    }
}

@MainActor
struct SettingsStoreTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "SettingsStoreTests.\(UUID().uuidString)")!
    }

    @Test("Defaults to the user's Downloads folder")
    func defaultsToDownloads() {
        let store = SettingsStore(defaults: makeDefaults())

        #expect(store.downloadFolder == FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0])
    }

    @Test("Persists the chosen folder across launches")
    func persistsFolder() {
        let defaults = makeDefaults()
        let folder = URL(filePath: "/tmp/My Videos", directoryHint: .isDirectory)

        SettingsStore(defaults: defaults).downloadFolder = folder

        #expect(SettingsStore(defaults: defaults).downloadFolder == folder)
    }

    @Test("Transcripts are on by default, in English and the system language")
    func defaultsTranscripts() {
        let store = SettingsStore(defaults: makeDefaults(), locale: Locale(identifier: "es_ES"))

        #expect(store.transcriptsEnabled)
        #expect(store.transcriptLanguages == "en,es")
        #expect(store.transcriptRequest == "en,es")
    }

    @Test("Doesn't repeat English when that's the system language")
    func defaultsTranscriptsInEnglish() {
        let store = SettingsStore(defaults: makeDefaults(), locale: Locale(identifier: "en_GB"))

        #expect(store.transcriptLanguages == "en")
    }

    @Test("Persists transcript choices across launches")
    func persistsTranscripts() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.transcriptsEnabled = false
        store.transcriptLanguages = "fr"

        let reloaded = SettingsStore(defaults: defaults)
        #expect(!reloaded.transcriptsEnabled)
        #expect(reloaded.transcriptLanguages == "fr")
    }

    @Test("Requests no transcripts when off or when no language is set")
    func omitsTranscriptRequest() {
        let store = SettingsStore(defaults: makeDefaults())

        store.transcriptsEnabled = false
        #expect(store.transcriptRequest == nil)

        store.transcriptsEnabled = true
        store.transcriptLanguages = "   "
        #expect(store.transcriptRequest == nil)

        store.transcriptLanguages = " en, es "
        #expect(store.transcriptRequest == "en,es")
    }
}
