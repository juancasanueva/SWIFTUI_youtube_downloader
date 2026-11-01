import Foundation
import Testing
@testable import youtubedownload

/// Runs the real `Process` plumbing against a shell script standing in for yt-dlp.
struct ProcessVideoDownloaderTests {
    private let video = YouTubeURL("https://youtu.be/abc")!
    private let destination = URL(filePath: "/tmp/videos", directoryHint: .isDirectory)
    private let file = URL(filePath: "/tmp/videos/clip.mp4")

    private func request(languages: String? = nil) -> DownloadRequest {
        DownloadRequest(video: video, destination: destination, transcriptLanguages: languages)
    }

    private func events(from downloader: ProcessVideoDownloader, languages: String? = nil) async throws -> [DownloadEvent] {
        var events: [DownloadEvent] = []
        for try await event in downloader.download(request(languages: languages)) {
            events.append(event)
        }
        return events
    }

    @Test("Emits the title, progress and final file when yt-dlp succeeds")
    func reportsSuccess() async throws {
        let downloader = try makeDownloader(script: """
        echo '[youtube] abc: Downloading'
        echo 'title=Clip'
        echo 'progress=50.0'
        echo 'file=/tmp/videos/clip.mp4'
        """)

        #expect(try await events(from: downloader) == [
            .title("Clip"),
            .progress(DownloadProgress(fraction: 0.5, speed: nil, timeRemaining: nil)),
            .finished(file),
        ])
    }

    @Test("Falls back to the destination folder when yt-dlp reports no file")
    func fallsBackToDestination() async throws {
        let downloader = try makeDownloader(script: "exit 0")

        #expect(try await events(from: downloader) == [.finished(destination)])
    }

    @Test("Fails with yt-dlp's own error message, read from stderr")
    func reportsToolError() async throws {
        let downloader = try makeDownloader(script: """
        echo 'ERROR: This video is unavailable' >&2
        exit 1
        """)

        await #expect(throws: DownloadError.failed("This video is unavailable")) {
            for try await _ in downloader.download(request()) {}
        }
    }

    @Test("Reports the exit code when yt-dlp fails silently")
    func reportsExitCode() async throws {
        let downloader = try makeDownloader(script: "exit 3")

        await #expect(throws: DownloadError.failed("yt-dlp exited with code 3.")) {
            for try await _ in downloader.download(request()) {}
        }
    }

    @Test("Fails clearly when yt-dlp is not installed")
    func reportsMissingTool() async throws {
        let downloader = ProcessVideoDownloader(searchDirectories: [URL(filePath: "/nonexistent")])

        await #expect(throws: DownloadError.toolNotFound) {
            for try await _ in downloader.download(request()) {}
        }
    }

    @Test("Passes the built arguments to the executable")
    func passesArguments() async throws {
        let downloader = try makeDownloader(script: #"""
        for last; do :; done
        echo "file=$last"
        """#)

        #expect(try await events(from: downloader) == [
            .finished(URL(filePath: "https://www.youtube.com/watch?v=abc")),
        ])
    }

    // MARK: - Transcripts

    /// Answers the video pass normally, and the transcript pass with `transcriptScript`.
    private func makeDownloader(transcriptScript: String, in directory: URL) throws -> ProcessVideoDownloader {
        try makeDownloader(script: """
        case "$*" in
        *--skip-download*)
        \(transcriptScript)
        ;;
        *)
        echo 'file=/tmp/videos/clip.mp4'
        ;;
        esac
        """, in: directory)
    }

    @Test("Fetches transcripts in a second pass, before reporting the video finished")
    func fetchesTranscripts() async throws {
        let directory = try makeScratchDirectory()
        let transcript = directory.appending(path: "clip.en.vtt")
        let downloader = try makeDownloader(transcriptScript: """
        touch '\(transcript.path)'
        echo '[info] Writing video subtitles to: \(transcript.path)'
        """, in: directory)

        #expect(try await events(from: downloader, languages: "en") == [
            .fetchingTranscripts,
            .transcript(transcript),
            .finished(file),
        ])
    }

    @Test("Keeps only subtitle files that exist")
    func ignoresMissingTranscripts() async throws {
        let directory = try makeScratchDirectory()
        let downloader = try makeDownloader(transcriptScript: """
        echo '[info] Writing video subtitles to: \(directory.path)/never-written.en.vtt'
        """, in: directory)

        #expect(try await events(from: downloader, languages: "en") == [.fetchingTranscripts, .finished(file)])
    }

    @Test("A language that fails is not a failure when another one was saved")
    func toleratesPartialTranscripts() async throws {
        let directory = try makeScratchDirectory()
        let transcript = directory.appending(path: "clip.en-orig.vtt")
        let downloader = try makeDownloader(transcriptScript: """
        touch '\(transcript.path)'
        echo '[info] Writing video subtitles to: \(transcript.path)'
        echo '[info] Writing video subtitles to: \(directory.path)/clip.en.vtt'
        echo "WARNING: Unable to download video subtitles for 'en': HTTP Error 429"
        """, in: directory)

        #expect(try await events(from: downloader, languages: "en") == [
            .fetchingTranscripts,
            .transcript(transcript),
            .finished(file),
        ])
    }

    @Test("Reports the reason when every language fails, and keeps the video")
    func reportsTotalTranscriptFailure() async throws {
        let directory = try makeScratchDirectory()
        let downloader = try makeDownloader(transcriptScript: """
        echo '[info] Writing video subtitles to: \(directory.path)/clip.en.vtt'
        echo "WARNING: Unable to download video subtitles for 'en': HTTP Error 429"
        """, in: directory)

        #expect(try await events(from: downloader, languages: "en") == [
            .fetchingTranscripts,
            .transcriptsFailed("Unable to download video subtitles for 'en': HTTP Error 429"),
            .finished(file),
        ])
    }

    @Test("Reports a transcript pass that exits with an error, and keeps the video")
    func reportsTranscriptPassError() async throws {
        let directory = try makeScratchDirectory()
        let downloader = try makeDownloader(transcriptScript: """
        echo 'ERROR: This video is unavailable'
        exit 1
        """, in: directory)

        #expect(try await events(from: downloader, languages: "en") == [
            .fetchingTranscripts,
            .transcriptsFailed("This video is unavailable"),
            .finished(file),
        ])
    }

    @Test("A video with no subtitles at all is not a failure")
    func toleratesNoSubtitles() async throws {
        let directory = try makeScratchDirectory()
        let downloader = try makeDownloader(transcriptScript: """
        echo '[info] There are no subtitles for the requested languages'
        """, in: directory)

        #expect(try await events(from: downloader, languages: "en") == [.fetchingTranscripts, .finished(file)])
    }

    @Test("Skips the transcript pass when transcripts are off")
    func skipsTranscriptsWhenOff() async throws {
        let directory = try makeScratchDirectory()
        let marker = directory.appending(path: "transcript-pass-ran")
        let downloader = try makeDownloader(transcriptScript: "touch '\(marker.path)'", in: directory)

        #expect(try await events(from: downloader, languages: nil) == [.finished(file)])
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test("Skips the transcript pass when the video fails")
    func skipsTranscriptsAfterFailure() async throws {
        let directory = try makeScratchDirectory()
        let marker = directory.appending(path: "transcript-pass-ran")
        let downloader = try makeDownloader(script: """
        case "$*" in
        *--skip-download*) touch '\(marker.path)' ;;
        *) echo 'ERROR: Gone'; exit 1 ;;
        esac
        """, in: directory)

        await #expect(throws: DownloadError.failed("Gone")) {
            for try await _ in downloader.download(request(languages: "en")) {}
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    // MARK: - Playlists

    @Test("Lists a playlist's videos, hiding unknown titles and skipping unusable lines")
    func listsPlaylist() async throws {
        let downloader = try makeDownloader(script: #"""
        printf 'aaa\tFirst video\n'
        printf 'bbb\tNA\n'
        printf 'not a valid id!\tThird\n'
        echo 'ccc'
        """#)
        let playlist = try #require(YouTubePlaylistURL("https://www.youtube.com/playlist?list=PL1"))

        let entries = try await downloader.playlistEntries(of: playlist)

        #expect(entries == [
            PlaylistEntry(video: YouTubeURL("https://youtu.be/aaa")!, title: "First video"),
            PlaylistEntry(video: YouTubeURL("https://youtu.be/bbb")!, title: nil),
        ])
    }

    @Test("Fails with yt-dlp's message when a playlist can't be read")
    func reportsPlaylistFailure() async throws {
        let downloader = try makeDownloader(script: """
        echo 'ERROR: The playlist does not exist'
        exit 1
        """)
        let playlist = try #require(YouTubePlaylistURL("https://www.youtube.com/playlist?list=PL1"))

        await #expect(throws: DownloadError.failed("The playlist does not exist")) {
            _ = try await downloader.playlistEntries(of: playlist)
        }
    }

    // MARK: - Cancellation

    @Test("Stops the process when the consumer cancels")
    func cancels() async throws {
        let directory = try makeScratchDirectory()
        let pidFile = directory.appending(path: "pid")
        let downloader = try makeDownloader(script: """
        echo $$ > '\(pidFile.path)'
        echo 'progress=1.0'
        exec sleep 30
        """, in: directory)

        try await cancelOnFirstProgress(downloader)
        try await expectStops(pidFile: pidFile)
    }

    @Test("Cancelling also stops child processes such as ffmpeg")
    func cancelsChildProcesses() async throws {
        let directory = try makeScratchDirectory()
        let pidFile = directory.appending(path: "child-pid")
        let downloader = try makeDownloader(script: """
        sleep 30 &
        echo $! > '\(pidFile.path)'
        echo 'progress=1.0'
        wait
        """, in: directory)

        try await cancelOnFirstProgress(downloader)
        try await expectStops(pidFile: pidFile)
    }

    @Test("Cancelling during the transcript pass stops that process too")
    func cancelsTranscriptPass() async throws {
        let directory = try makeScratchDirectory()
        let pidFile = directory.appending(path: "pid")
        let downloader = try makeDownloader(transcriptScript: """
        echo $$ > '\(pidFile.path)'
        exec sleep 30
        """, in: directory)

        let task = Task {
            for try await event in downloader.download(request(languages: "en")) {
                if event == .fetchingTranscripts {
                    while (try? String(contentsOf: pidFile, encoding: .utf8))?.isEmpty != false { await Task.yield() }
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        _ = try await task.value
        try await expectStops(pidFile: pidFile)
    }

    private func cancelOnFirstProgress(_ downloader: ProcessVideoDownloader) async throws {
        let task = Task {
            for try await event in downloader.download(request()) {
                if case .progress = event { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        _ = try await task.value
    }

    private func expectStops(pidFile: URL) async throws {
        let text = try String(contentsOf: pidFile, encoding: .utf8)
        let pid = try #require(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        var isAlive = true
        for _ in 0..<500 where isAlive {
            isAlive = kill(pid, 0) == 0
            if isAlive { try await Task.sleep(for: .milliseconds(10)) }
        }
        #expect(!isAlive)
    }

    // MARK: - Helpers

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
