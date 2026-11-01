import Foundation
import Testing
@testable import youtubedownload

private struct IdleDownloader: VideoDownloading {
    func download(_ video: YouTubeURL, to destination: URL) -> AsyncThrowingStream<DownloadEvent, Error> {
        AsyncThrowingStream { _ in }
    }
}

@MainActor
struct StatusItemControllerTests {
    private let downloads = DownloadStore(downloader: IdleDownloader())

    private func makeController() -> StatusItemController {
        let defaults = UserDefaults(suiteName: "StatusItemControllerTests.\(UUID().uuidString)")!
        return StatusItemController(downloads: downloads, settings: SettingsStore(defaults: defaults), openSettings: {})
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

    @Test("A result that arrived while closed survives opening, and closing clears it")
    func resultIsClearedOnlyAfterBeingSeen() async throws {
        let controller = makeController()
        let failure = DownloadStore.Phase.failed("Enter a valid YouTube video URL.")
        try await Task.sleep(for: .seconds(1))
        downloads.start(urlText: "not a url", destination: URL(filePath: "/tmp"))

        controller.togglePanel()
        try await waitUntil { controller.isPanelOpen }
        #expect(downloads.phase == failure)

        controller.togglePanel()
        try await waitUntil { downloads.phase == .idle }
        #expect(downloads.phase == .idle)
    }

    @Test("Opening the panel leaves a running download alone")
    func openingKeepsRunningDownload() {
        let controller = makeController()
        downloads.start(urlText: "https://youtu.be/abc", destination: URL(filePath: "/tmp"))

        controller.togglePanel()

        #expect(downloads.isDownloading)
    }

    @Test("The icon shows whether a download is running")
    func iconReflectsDownload() {
        #expect(StatusItemLook(isDownloading: false).symbolName == "arrow.down.circle")
        #expect(StatusItemLook(isDownloading: true).symbolName == "arrow.down.circle.fill")
        #expect(StatusItemLook(isDownloading: false).accessibilityLabel == "YouTube Downloader")
        #expect(StatusItemLook(isDownloading: true).accessibilityLabel == "YouTube Downloader, downloading")
    }
}
