import Foundation
import Testing
@testable import youtubedownload

private struct FakeDownloader: VideoDownloading {
    let stream: AsyncThrowingStream<DownloadEvent, Error>
    let received = Received()

    final class Received: @unchecked Sendable {
        var video: YouTubeURL?
        var destination: URL?
    }

    func download(_ video: YouTubeURL, to destination: URL) -> AsyncThrowingStream<DownloadEvent, Error> {
        received.video = video
        received.destination = destination
        return stream
    }
}

@MainActor
struct DownloadStoreTests {
    private let validURL = "https://youtu.be/abc"
    private let destination = URL(filePath: "/tmp/videos", directoryHint: .isDirectory)

    @Test("Rejects an invalid URL without starting a download")
    func rejectsInvalidURL() {
        let (stream, _) = AsyncThrowingStream<DownloadEvent, Error>.makeStream()
        let downloader = FakeDownloader(stream: stream)
        let store = DownloadStore(downloader: downloader)

        store.start(urlText: "https://example.com", destination: destination)

        #expect(store.phase == .failed("Enter a valid YouTube video URL."))
        #expect(downloader.received.video == nil)
    }

    @Test("Moves from downloading through progress to finished")
    func runsToCompletion() async {
        let (stream, continuation) = AsyncThrowingStream<DownloadEvent, Error>.makeStream()
        let downloader = FakeDownloader(stream: stream)
        let store = DownloadStore(downloader: downloader)
        let file = URL(filePath: "/tmp/videos/clip.mp4")

        store.start(urlText: validURL, destination: destination)
        #expect(store.phase == .downloading(progress: nil))
        #expect(store.isDownloading)
        #expect(downloader.received.video?.url.absoluteString == validURL)
        #expect(downloader.received.destination == destination)

        continuation.yield(.progress(0.5))
        await waitUntil { store.phase == .downloading(progress: 0.5) }

        continuation.yield(.finished(file))
        continuation.finish()
        await store.currentDownload?.value

        #expect(store.phase == .finished(file))
        #expect(!store.isDownloading)
    }

    @Test("Shows the failure message when the download fails")
    func reportsFailure() async {
        let (stream, continuation) = AsyncThrowingStream<DownloadEvent, Error>.makeStream()
        let store = DownloadStore(downloader: FakeDownloader(stream: stream))

        store.start(urlText: validURL, destination: destination)
        continuation.finish(throwing: DownloadError.failed("This video is unavailable"))
        await store.currentDownload?.value

        #expect(store.phase == .failed("This video is unavailable"))
    }

    @Test("Ignores a second start while a download is running")
    func ignoresSecondStart() {
        let (stream, _) = AsyncThrowingStream<DownloadEvent, Error>.makeStream()
        let downloader = FakeDownloader(stream: stream)
        let store = DownloadStore(downloader: downloader)

        store.start(urlText: validURL, destination: destination)
        store.start(urlText: "https://youtu.be/other", destination: destination)

        #expect(downloader.received.video?.url.absoluteString == validURL)
    }

    @Test("Cancelling returns to idle")
    func cancels() async {
        let (stream, _) = AsyncThrowingStream<DownloadEvent, Error>.makeStream()
        let store = DownloadStore(downloader: FakeDownloader(stream: stream))

        store.start(urlText: validURL, destination: destination)
        let download = store.currentDownload
        store.cancel()
        await download?.value

        #expect(store.phase == .idle)
    }

    @Test("Clearing keeps a running download and resets a finished one")
    func clearsOnlyTerminalPhases() async {
        let (stream, continuation) = AsyncThrowingStream<DownloadEvent, Error>.makeStream()
        let store = DownloadStore(downloader: FakeDownloader(stream: stream))

        store.start(urlText: validURL, destination: destination)
        store.clearResult()
        #expect(store.phase == .downloading(progress: nil))

        continuation.yield(.finished(destination))
        continuation.finish()
        await store.currentDownload?.value
        store.clearResult()
        #expect(store.phase == .idle)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() {
            await Task.yield()
        }
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
}
