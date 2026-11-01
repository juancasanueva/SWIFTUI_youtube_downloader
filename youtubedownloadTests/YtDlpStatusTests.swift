import Foundation
import Testing
@testable import youtubedownload

@MainActor
struct YtDlpStatusTests {
    private let executable = URL(filePath: "/opt/homebrew/bin/yt-dlp")

    @Test("Reports where yt-dlp is when it's installed")
    func reportsInstalled() {
        let status = YtDlpStatus(locate: { executable })

        #expect(status.isInstalled)
        #expect(status.location == executable)
    }

    @Test("Reports when yt-dlp is missing")
    func reportsMissing() {
        let status = YtDlpStatus(locate: { nil })

        #expect(!status.isInstalled)
        #expect(status.location == nil)
    }

    @Test("Notices an install, and an uninstall, on the next check")
    func refreshes() {
        var found: URL?
        let status = YtDlpStatus(locate: { found })
        #expect(!status.isInstalled)

        found = executable
        #expect(!status.isInstalled)
        status.refresh()
        #expect(status.isInstalled)

        found = nil
        status.refresh()
        #expect(!status.isInstalled)
    }

    @Test("The instructions also install ffmpeg, which Homebrew's yt-dlp doesn't bring")
    func givesInstallCommand() {
        #expect(YtDlpStatus.installCommand == "brew install yt-dlp ffmpeg")
    }
}

struct YtDlpVersionTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents(year: year, month: month, day: day)
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    @Test("Reads the release date from the version", arguments: ["2026.03.17", "2026.03.17.232908", " 2026.03.17\n"])
    func parses(text: String) throws {
        let version = try #require(YtDlpVersion(text))
        #expect(version.released == date(2026, 3, 17))
        #expect(version.text == "2026.03.17")
    }

    @Test("Ignores text that isn't a dated version", arguments: ["", "nightly", "2026.13.40", "2026.03", "abc.de.fg"])
    func rejects(text: String) {
        #expect(YtDlpVersion(text) == nil)
    }

    @Test("Counts as outdated only after more than 90 days")
    func measuresAge() throws {
        let version = try #require(YtDlpVersion("2026.03.17"))

        #expect(!version.isOutdated(at: date(2026, 3, 17)))
        #expect(!version.isOutdated(at: date(2026, 6, 15)))
        #expect(version.isOutdated(at: date(2026, 6, 16)))
        #expect(version.isOutdated(at: date(2026, 11, 1)))
    }
}

@MainActor
struct YtDlpStatusVersionTests {
    private let executable = URL(filePath: "/opt/homebrew/bin/yt-dlp")
    private let now = YtDlpVersion("2026.11.01")!.released

    @Test("Flags a version the user should update")
    func flagsOldVersion() async {
        let status = YtDlpStatus(locate: { executable }, readVersion: { "2026.03.17" }, now: { now })

        await status.refreshVersion()

        #expect(status.version?.text == "2026.03.17")
        #expect(status.isOutdated)
    }

    @Test("Doesn't flag a recent version")
    func acceptsRecentVersion() async {
        let status = YtDlpStatus(locate: { executable }, readVersion: { "2026.10.26" }, now: { now })

        await status.refreshVersion()

        #expect(status.version?.text == "2026.10.26")
        #expect(!status.isOutdated)
    }

    @Test("Doesn't warn when the version can't be read")
    func staysQuietWithoutVersion() async {
        let status = YtDlpStatus(locate: { executable }, readVersion: { nil }, now: { now })

        await status.refreshVersion()

        #expect(status.version == nil)
        #expect(status.isInstalled)
        #expect(!status.isOutdated)
    }

    @Test("Doesn't warn before the version has been read")
    func staysQuietBeforeReading() {
        let status = YtDlpStatus(locate: { executable }, readVersion: { "2026.03.17" }, now: { now })

        #expect(!status.isOutdated)
    }

    @Test("Forgets the version once yt-dlp is gone")
    func forgetsVersionWhenMissing() async {
        var found: URL? = executable
        let status = YtDlpStatus(locate: { found }, readVersion: { "2026.03.17" }, now: { now })
        await status.refreshVersion()
        #expect(status.isOutdated)

        found = nil
        status.refresh()
        await status.refreshVersion()

        #expect(status.version == nil)
        #expect(!status.isOutdated)
    }

    @Test("Picks up an update on the next check")
    func noticesUpdate() async {
        var installed = "2026.03.17"
        let status = YtDlpStatus(locate: { executable }, readVersion: { installed }, now: { now })
        await status.refreshVersion()
        #expect(status.isOutdated)

        installed = "2026.10.26"
        await status.refreshVersion()

        #expect(!status.isOutdated)
    }
}

/// The command has to update the copy that actually runs: `brew upgrade` skips a pip install.
struct YtDlpUpdateCommandTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("A Homebrew install, reached through its symlink, uses brew upgrade")
    func homebrewCopy() throws {
        let root = try makeDirectory()
        let cellar = root.appending(path: "Cellar/yt-dlp/2026.03.17/bin")
        try FileManager.default.createDirectory(at: cellar, withIntermediateDirectories: true)
        let target = cellar.appending(path: "yt-dlp")
        try "#!/bin/sh\n".write(to: target, atomically: true, encoding: .utf8)
        let bin = root.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let link = bin.appending(path: "yt-dlp")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(YtDlpStatus.updateCommand(for: link) == "brew upgrade yt-dlp")
    }

    @Test("Any other copy, such as one from pip, gets replaced by Homebrew's")
    func otherCopy() throws {
        let file = try makeDirectory().appending(path: "yt-dlp")
        try "#!/bin/sh\n".write(to: file, atomically: true, encoding: .utf8)

        #expect(YtDlpStatus.updateCommand(for: file) == "brew install yt-dlp && brew link --overwrite yt-dlp")
    }
}

struct ProcessVideoDownloaderLocationTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeTool(in directory: URL, permissions: Int) throws -> URL {
        let file = directory.appending(path: "yt-dlp")
        try "#!/bin/sh\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path)
        return file
    }

    @Test("Finds the executable in the first directory that has it")
    func findsExecutable() throws {
        let empty = try makeDirectory()
        let directory = try makeDirectory()
        let tool = try makeTool(in: directory, permissions: 0o755)

        let downloader = ProcessVideoDownloader(searchDirectories: [empty, directory])

        #expect(downloader.locateExecutable() == tool)
    }

    @Test("Finds nothing when it isn't in any directory")
    func findsNothing() throws {
        let downloader = ProcessVideoDownloader(searchDirectories: [try makeDirectory()])

        #expect(downloader.locateExecutable() == nil)
    }

    @Test("Doesn't count a file that can't be run")
    func ignoresNonExecutable() throws {
        let directory = try makeDirectory()
        _ = try makeTool(in: directory, permissions: 0o644)

        let downloader = ProcessVideoDownloader(searchDirectories: [directory])

        #expect(downloader.locateExecutable() == nil)
    }

    @Test("Reads the installed version")
    func readsVersion() async throws {
        let directory = try makeDirectory()
        let tool = try makeTool(in: directory, permissions: 0o755)
        try "#!/bin/sh\necho 'WARNING: something'\necho 2026.10.26\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)

        let version = await ProcessVideoDownloader(searchDirectories: [directory]).installedVersion()

        #expect(version == "2026.10.26")
    }

    @Test("Reports no version when yt-dlp is missing or broken")
    func readsNoVersion() async throws {
        let missing = ProcessVideoDownloader(searchDirectories: [try makeDirectory()])
        #expect(await missing.installedVersion() == nil)

        let directory = try makeDirectory()
        let tool = try makeTool(in: directory, permissions: 0o755)
        try "#!/bin/sh\necho 2026.10.26\nexit 1\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        #expect(await ProcessVideoDownloader(searchDirectories: [directory]).installedVersion() == nil)
    }

    @Test("The download error gives the same install command as Settings")
    func errorUsesSameCommand() {
        #expect(DownloadError.toolNotFound.localizedDescription.hasSuffix(YtDlpStatus.installCommand))
    }
}
