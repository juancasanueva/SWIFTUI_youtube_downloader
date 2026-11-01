import Foundation
import Testing
@testable import youtubedownload

private struct IdleDownloader: VideoDownloading {
    func download(_ request: DownloadRequest) -> AsyncThrowingStream<DownloadEvent, Error> {
        AsyncThrowingStream { _ in }
    }

    func playlistEntries(of playlist: YouTubePlaylistURL) async throws -> [PlaylistEntry] {
        []
    }
}

/// Serialized because each test adds a real menu bar item, and a new item moves the others
/// just as a popover may be trying to anchor to one.
@MainActor
@Suite(.serialized)
struct StatusItemControllerTests {
    private let queue: DownloadQueue

    init() {
        let historyFile = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/history.json")
        queue = DownloadQueue(downloader: IdleDownloader(), history: HistoryStore(fileURL: historyFile))
    }

    private func makeController() -> StatusItemController {
        let defaults = UserDefaults(suiteName: "StatusItemControllerTests.\(UUID().uuidString)")!
        return StatusItemController(queue: queue, settings: SettingsStore(defaults: defaults), openSettings: {})
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<300 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("Toggling opens the panel, and toggling again closes it")
    func togglesPanel() async throws {
        let controller = makeController()
        #expect(!controller.isPanelOpen)

        // A status item created this instant has no place in the menu bar to point at yet.
        try await Task.sleep(for: .seconds(1))

        controller.togglePanel()
        try await waitUntil { controller.isPanelOpen }
        #expect(controller.isPanelOpen)

        controller.togglePanel()
        try await waitUntil { !controller.isPanelOpen }
        #expect(!controller.isPanelOpen)
    }

    @Test("Closing the panel forgets the input error")
    func closingClearsInputError() async throws {
        let controller = makeController()
        try await Task.sleep(for: .seconds(1))
        _ = queue.submit(urlText: "not a url", destination: URL(filePath: "/tmp"), transcriptLanguages: nil, quality: .p1080)

        controller.togglePanel()
        try await waitUntil { controller.isPanelOpen }
        #expect(queue.inputError != nil)

        controller.togglePanel()
        try await waitUntil { queue.inputError == nil }
        #expect(queue.inputError == nil)
    }

    @Test("Opening the panel leaves a running download alone")
    func openingKeepsRunningDownload() {
        let controller = makeController()
        _ = queue.submit(urlText: "https://youtu.be/abc", destination: URL(filePath: "/tmp"), transcriptLanguages: nil, quality: .p1080)

        controller.togglePanel()

        #expect(queue.isBusy)
    }

    @Test("The icon shows whether a download is running")
    func iconReflectsDownload() {
        #expect(StatusItemLook(isDownloading: false).symbolName == "arrow.down.circle")
        #expect(StatusItemLook(isDownloading: true).symbolName == "arrow.down.circle.fill")
        #expect(StatusItemLook(isDownloading: false).accessibilityLabel == "YouTube Downloader")
        #expect(StatusItemLook(isDownloading: true).accessibilityLabel == "YouTube Downloader, downloading")
    }
}
