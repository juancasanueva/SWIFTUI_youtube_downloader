import AppKit
import Foundation
import Testing
@testable import youtubedownload

@MainActor
@Suite("App updating")
struct AppUpdatingTests {
    @Test func eachInvocationStartsExactlyOneCheck() {
        let updater = FakeAppUpdater()
        updater.checkForUpdates()
        #expect(updater.checkCount == 1)
        updater.checkForUpdates()
        #expect(updater.checkCount == 2)
    }

    @Test(arguments: [true, false])
    func thePersistedPreferenceIsWrittenExactlyOnce(preference: Bool) {
        // Start from an updater that disagrees, so a "write only if different" policy fails.
        let updater = FakeAppUpdater(automaticallyChecksForUpdates: !preference)
        AutomaticUpdateChecksPolicy.apply(preference: preference, to: updater)
        #expect(updater.automaticallyChecksForUpdates == preference)
        #expect(updater.automaticWriteCount == 1)
    }

    @Test func anAgreeingPreferenceIsStillWritten() {
        let updater = FakeAppUpdater(automaticallyChecksForUpdates: false)
        AutomaticUpdateChecksPolicy.apply(preference: false, to: updater)
        #expect(updater.automaticWriteCount == 1)
    }

    @Test(arguments: [true, false])
    func theCommandIsEnabledExactlyWhileACheckCanRun(canCheck: Bool) {
        #expect(UpdateCommandEnablement.isEnabled(canCheckForUpdates: canCheck) == canCheck)
    }
}

@Suite("Automatic update checks")
struct AutomaticUpdateChecksTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "update-tests-\(UUID().uuidString)")!
    }

    @Test func aFreshInstallDoesNotCheckAutomatically() {
        #expect(!AutomaticUpdateChecks(defaults: makeDefaults()).isEnabled)
    }

    @Test func theAnswerPersistsUnderItsKey() {
        let defaults = makeDefaults()
        AutomaticUpdateChecks(defaults: defaults).isEnabled = true
        #expect(defaults.bool(forKey: "updates.automaticChecksEnabled"))
        #expect(AutomaticUpdateChecks(defaults: defaults).isEnabled)
        AutomaticUpdateChecks(defaults: defaults).isEnabled = false
        #expect(!AutomaticUpdateChecks(defaults: defaults).isEnabled)
    }
}

@Suite("Update check presentation")
struct UpdateCheckPresentationTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func neverCheckedSaysSoWithoutADate() {
        #expect(UpdateCheckPresentation(lastCheck: nil, now: now).label == "Never checked")
    }

    @Test func aRecordedCheckReadsRelativeToNow() {
        let label = UpdateCheckPresentation(
            lastCheck: now.addingTimeInterval(-2 * 3600),
            now: now,
            locale: Locale(identifier: "en_US")
        ).label
        #expect(label == "Last checked 2 hours ago")
    }
}

private struct IdleDownloader: VideoDownloading {
    func download(_ request: DownloadRequest) -> AsyncThrowingStream<DownloadEvent, Error> {
        AsyncThrowingStream { _ in }
    }

    func playlistEntries(of playlist: YouTubePlaylistURL) async throws -> [PlaylistEntry] {
        []
    }
}

/// Serialized because each test adds a real menu bar item, as in `StatusItemControllerTests`.
@MainActor
@Suite("Context menu updates", .serialized)
struct ContextMenuUpdatesTests {
    private func makeController(updater: FakeAppUpdater?, openSettings: @escaping () -> Void = {}) -> StatusItemController {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let queue = DownloadQueue(
            downloader: IdleDownloader(),
            history: HistoryStore(fileURL: directory.appending(path: "history.json"))
        )
        let defaults = UserDefaults(suiteName: "menu-tests-\(UUID().uuidString)")!
        return StatusItemController(
            queue: queue,
            settings: SettingsStore(defaults: defaults),
            updater: updater,
            openSettings: openSettings, openAbout: {}
        )
    }

    private func item(_ title: String, in menu: NSMenu) throws -> NSMenuItem {
        try #require(menu.items.first { $0.title == title })
    }

    @Test func theMenuOffersAboutUpdatesSettingsAndQuitInOrder() {
        let menu = makeController(updater: FakeAppUpdater()).makeContextMenu()

        #expect(menu.items.map(\.title) == ["About yt_downloader", "", "Check for Updates…", "Settings…", "", "Quit"])
    }

    @Test func checkForUpdatesStartsOneCheck() throws {
        let updater = FakeAppUpdater()
        // Menu item targets are weak, so the controller has to outlive the menu.
        let controller = makeController(updater: updater)
        let menu = controller.makeContextMenu()

        let index = menu.index(of: try item("Check for Updates…", in: menu))
        menu.performActionForItem(at: index)

        #expect(updater.checkCount == 1)
    }

    @Test func theItemIsDisabledWhileACheckIsRunning() throws {
        let menu = makeController(updater: FakeAppUpdater(canCheckForUpdates: false)).makeContextMenu()

        #expect(try !item("Check for Updates…", in: menu).isEnabled)
    }

    @Test func theItemIsDisabledWithoutAnUpdater() throws {
        let menu = makeController(updater: nil).makeContextMenu()

        #expect(try !item("Check for Updates…", in: menu).isEnabled)
    }

    @Test func settingsStaysAvailableWhileACheckIsRunning() throws {
        var opened = 0
        let controller = makeController(updater: FakeAppUpdater(canCheckForUpdates: false)) { opened += 1 }
        let menu = controller.makeContextMenu()

        let settings = try item("Settings…", in: menu)
        #expect(settings.isEnabled)
        menu.performActionForItem(at: menu.index(of: settings))

        #expect(opened == 1)
    }
}

@Suite("Bundle update keys")
struct BundleUpdateKeysTests {
    private static let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()

    private func updateKeys() throws -> [String: Any] {
        let path = "youtubedownload/Resources/YouTubeDownloader-Info.plist"
        let data = try Data(contentsOf: Self.sourceRoot.appending(path: path))
        return try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func theBundleCarriesTheFeedAndThePublicKey() throws {
        let info = try updateKeys()
        #expect(info["SUFeedURL"] as? String == "https://juancasanueva.github.io/SWIFTUI_youtube_downloader/appcast.xml")
        let key = try #require(info["SUPublicEDKey"] as? String)
        #expect(Data(base64Encoded: key)?.count == 32)
        // Shared with the author's other apps. A different key strands every installed copy.
        #expect(key == "jqReS/cOvK94pbRz/4DwMBTRMwh/0Nf5OJZ5SAfZDVs=")
    }

    /// The bundle states the daily check rather than leaning on Sparkle's default.
    @Test func theBundleChecksOnceADay() throws {
        #expect(try updateKeys()["SUScheduledCheckInterval"] as? Int == 86_400)
    }

    @Test func automaticChecksAreNotEnabledByTheBundle() throws {
        let info = try updateKeys()
        #expect(info["SUEnableAutomaticChecks"] == nil)
        #expect(info["SUAutomaticallyUpdate"] == nil)
    }

    /// The partial Info.plist is merged into the bundle's, never shipped as a resource.
    @Test func thePartialInfoPlistIsNotCopiedAsAResource() throws {
        let project = try String(
            contentsOf: Self.sourceRoot.appending(path: "youtubedownload.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        #expect(project.contains("\"Resources/YouTubeDownloader-Info.plist\","))
    }

    /// The framework stays behind one adapter.
    @Test func onlyTheAdapterImportsSparkle() throws {
        let sources = Self.sourceRoot.appending(path: "youtubedownload")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let importing = try files.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .filter { try String(contentsOf: $0, encoding: .utf8).contains("import Sparkle") }
            .map(\.lastPathComponent)
        #expect(importing == ["SparkleUpdateChecker.swift"])
    }

    /// Sparkle flips `canCheckForUpdates` to true inside `startUpdater()`, before the observers exist;
    /// without `.initial`, "Check for Updates…" stays disabled.
    @Test func adapterObservesTheUpdatersCurrentValues() throws {
        let adapter = Self.sourceRoot.appending(path: "youtubedownload/Updates/SparkleUpdateChecker.swift")
        let source = try String(contentsOf: adapter, encoding: .utf8)
        #expect(source.components(separatedBy: "options: [.initial, .new]").count - 1 == 2)
        #expect(!source.contains("options: [.new]"))
    }
}
