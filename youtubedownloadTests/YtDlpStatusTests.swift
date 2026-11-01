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

    @Test("The download error gives the same install command as Settings")
    func errorUsesSameCommand() {
        #expect(DownloadError.toolNotFound.localizedDescription.hasSuffix(YtDlpStatus.installCommand))
    }
}
