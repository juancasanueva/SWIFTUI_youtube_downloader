import Foundation
import Testing
@testable import youtubedownload

/// Runs the real `Process` plumbing against a shell script standing in for yt-dlp.
struct ProcessVideoDownloaderTests {
    private let video = YouTubeURL("https://youtu.be/abc")!
    private let destination = URL(filePath: "/tmp/videos", directoryHint: .isDirectory)

    @Test("Emits progress and the final file when yt-dlp succeeds")
    func reportsSuccess() async throws {
        let downloader = try makeDownloader(script: """
        echo '[youtube] abc: Downloading'
        echo 'progress=50.0'
        echo 'file=/tmp/videos/clip.mp4'
        """)

        var events: [DownloadEvent] = []
        for try await event in downloader.download(video, to: destination) {
            events.append(event)
        }

        #expect(events == [.progress(0.5), .finished(URL(filePath: "/tmp/videos/clip.mp4"))])
    }

    @Test("Falls back to the destination folder when yt-dlp reports no file")
    func fallsBackToDestination() async throws {
        let downloader = try makeDownloader(script: "exit 0")

        var events: [DownloadEvent] = []
        for try await event in downloader.download(video, to: destination) {
            events.append(event)
        }

        #expect(events == [.finished(destination)])
    }

    @Test("Fails with yt-dlp's own error message, read from stderr")
    func reportsToolError() async throws {
        let downloader = try makeDownloader(script: """
        echo 'ERROR: This video is unavailable' >&2
        exit 1
        """)

        await #expect(throws: DownloadError.failed("This video is unavailable")) {
            for try await _ in downloader.download(video, to: destination) {}
        }
    }

    @Test("Reports the exit code when yt-dlp fails silently")
    func reportsExitCode() async throws {
        let downloader = try makeDownloader(script: "exit 3")

        await #expect(throws: DownloadError.failed("yt-dlp exited with code 3.")) {
            for try await _ in downloader.download(video, to: destination) {}
        }
    }

    @Test("Fails clearly when yt-dlp is not installed")
    func reportsMissingTool() async throws {
        let downloader = ProcessVideoDownloader(searchDirectories: [URL(filePath: "/nonexistent")])

        await #expect(throws: DownloadError.toolNotFound) {
            for try await _ in downloader.download(video, to: destination) {}
        }
    }

    @Test("Passes the built arguments to the executable")
    func passesArguments() async throws {
        let downloader = try makeDownloader(script: #"""
        for last; do :; done
        echo "file=$last"
        """#)

        var events: [DownloadEvent] = []
        for try await event in downloader.download(video, to: destination) {
            events.append(event)
        }

        #expect(events == [.finished(URL(filePath: "https://youtu.be/abc"))])
    }

    @Test("Stops the process when the consumer cancels")
    func cancels() async throws {
        let directory = try makeScratchDirectory()
        let pidFile = directory.appending(path: "pid")
        let downloader = try makeDownloader(script: """
        echo $$ > '\(pidFile.path)'
        echo 'progress=1.0'
        exec sleep 30
        """, in: directory)

        let task = Task {
            for try await event in downloader.download(video, to: destination) {
                if case .progress = event { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        _ = try await task.value

        let text = try String(contentsOf: pidFile, encoding: .utf8)
        let pid = try #require(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        var isAlive = true
        for _ in 0..<500 where isAlive {
            isAlive = kill(pid, 0) == 0
            if isAlive { try await Task.sleep(for: .milliseconds(10)) }
        }
        #expect(!isAlive)
    }

    private func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeDownloader(script: String, in directory: URL? = nil) throws -> ProcessVideoDownloader {
        let directory = try directory ?? makeScratchDirectory()
        let executable = directory.appending(path: "yt-dlp")
        try "#!/bin/sh\n\(script)\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return ProcessVideoDownloader(searchDirectories: [directory])
    }
}
