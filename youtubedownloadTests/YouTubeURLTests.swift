import Foundation
import Testing
@testable import youtubedownload

struct YouTubeURLTests {
    @Test("Reduces every video URL form to the canonical watch URL", arguments: [
        "https://www.youtube.com/watch?v=jNQXAC9IVRw",
        "http://youtube.com/watch?v=jNQXAC9IVRw&list=PL123",
        "https://m.youtube.com/watch?v=jNQXAC9IVRw",
        "https://music.youtube.com/watch?v=jNQXAC9IVRw",
        "HTTPS://WWW.YOUTUBE.COM/watch?v=jNQXAC9IVRw",
        "https://youtu.be/jNQXAC9IVRw",
        "https://youtu.be/jNQXAC9IVRw?si=shared",
        "https://www.youtube.com/shorts/jNQXAC9IVRw",
        "https://www.youtube.com/live/jNQXAC9IVRw",
        "https://www.youtube.com/embed/jNQXAC9IVRw",
    ])
    func acceptsVideoURLs(text: String) throws {
        let url = try #require(YouTubeURL(text))
        #expect(url.url.absoluteString == "https://www.youtube.com/watch?v=jNQXAC9IVRw")
    }

    @Test("Trims whitespace and assumes https when the scheme is missing")
    func normalizesPastedText() throws {
        let url = try #require(YouTubeURL("  youtube.com/watch?v=abc\n"))
        #expect(url.url.absoluteString == "https://www.youtube.com/watch?v=abc")
    }

    @Test("Rejects anything that is not a single YouTube video", arguments: [
        "",
        "not a url",
        "--exec=rm",
        "ftp://www.youtube.com/watch?v=abc",
        "file:///etc/passwd",
        "https://youtube.com.evil.example/watch?v=abc",
        "https://evil.example/watch?v=abc",
        "https://www.youtube.com",
        "https://www.youtube.com/watch",
        "https://www.youtube.com/watch?v=",
        "https://www.youtube.com/playlist?list=PL123",
        "https://www.youtube.com/@channel",
        "https://youtu.be/",
        "https://www.youtube.com/embed/videoseries?list=PL123",
        "https://youtu.be/videoseries?list=PL123",
        "https://www.youtube.com:8443/watch?v=abc",
        "https://evil@www.youtube.com/watch?v=abc",
        "https://www.youtube.com/watch/foo/bar?v=abc",
        "https://www.youtube.com/watch?v=x%0Ahttps://evil.example/",
        "https://www.youtube.com/watch?v=x%20--exec%20rm",
    ])
    func rejectsOtherInput(text: String) {
        #expect(YouTubeURL(text) == nil)
    }
}

struct YouTubePlaylistURLTests {
    @Test("Reduces playlist URLs to the canonical form", arguments: [
        "https://www.youtube.com/playlist?list=PL123-abc_D",
        "http://youtube.com/playlist?list=PL123-abc_D&si=shared",
        "music.youtube.com/playlist?list=PL123-abc_D",
    ])
    func acceptsPlaylists(text: String) throws {
        let playlist = try #require(YouTubePlaylistURL(text))
        #expect(playlist.url.absoluteString == "https://www.youtube.com/playlist?list=PL123-abc_D")
    }

    @Test("Rejects everything else", arguments: [
        "https://www.youtube.com/playlist",
        "https://www.youtube.com/playlist?list=",
        "https://www.youtube.com/playlist?list=a%20--exec",
        "https://evil.example/playlist?list=PL123",
        "https://www.youtube.com:8443/playlist?list=PL123",
        "https://evil@www.youtube.com/playlist?list=PL123",
        "https://www.youtube.com/watch?v=abc&list=PL123",
        "not a url",
    ])
    func rejectsOtherInput(text: String) {
        #expect(YouTubePlaylistURL(text) == nil)
    }
}

struct YtDlpCommandTests {
    private let destination = URL(filePath: "/tmp/My Videos", directoryHint: .isDirectory)

    @Test("Builds arguments that download one mp4 into the destination")
    func buildsVideoArguments() throws {
        let video = try #require(YouTubeURL("https://youtu.be/abc"))

        #expect(YtDlpCommand.videoArguments(for: video, destination: destination) == [
            "-t", "mp4",
            "--no-playlist",
            "--newline",
            "--progress",
            "--no-simulate",
            "--no-warnings",
            "--print", "before_dl:title=%(title)s",
            "--print", "after_move:file=%(filepath)s",
            "--progress-template", "download:progress=%(progress._percent)s\t%(progress._speed_str)s\t%(progress._eta_str)s",
            "-P", "/tmp/My Videos/",
            "-o", "%(title)s [%(id)s].%(ext)s",
            "--",
            "https://www.youtube.com/watch?v=abc",
        ])
    }

    @Test("Builds arguments that fetch only subtitles, named after the video")
    func buildsTranscriptArguments() throws {
        let video = try #require(YouTubeURL("https://youtu.be/abc"))

        #expect(YtDlpCommand.transcriptArguments(for: video, destination: destination, languages: "en,es") == [
            "--no-playlist",
            "--skip-download",
            "--write-subs",
            "--write-auto-subs",
            "--ignore-errors",
            "--sub-langs", "en-orig,es-orig,en,es",
            "--sub-format", "vtt/best",
            "-P", "/tmp/My Videos/",
            "-o", "%(title)s [%(id)s].%(ext)s",
            "--",
            "https://www.youtube.com/watch?v=abc",
        ])
    }

    @Test("Builds arguments that list a playlist without downloading it")
    func buildsPlaylistArguments() throws {
        let playlist = try #require(YouTubePlaylistURL("https://www.youtube.com/playlist?list=PL1"))

        #expect(YtDlpCommand.playlistArguments(for: playlist) == [
            "--yes-playlist",
            "--flat-playlist",
            "--no-warnings",
            "--print", "%(id)s\t%(title)s",
            "--",
            "https://www.youtube.com/playlist?list=PL1",
        ])
    }
}

struct YtDlpOutputLineTests {
    @Test("Reads progress as a 0...1 fraction with speed and time remaining")
    func parsesProgress() {
        #expect(YtDlpOutputLine("progress=25.5\t  11.17MiB/s\t00:42") == .progress(
            DownloadProgress(fraction: 0.255, speed: "11.17MiB/s", timeRemaining: "00:42")
        ))
    }

    @Test("Hides values yt-dlp does not know yet")
    func parsesUnknownProgressValues() {
        #expect(YtDlpOutputLine("progress=0.5\t Unknown B/s\tUnknown") == .progress(
            DownloadProgress(fraction: 0.005, speed: nil, timeRemaining: nil)
        ))
        #expect(YtDlpOutputLine("progress=100.0\t1.02MiB/s\tNA") == .progress(
            DownloadProgress(fraction: 1, speed: "1.02MiB/s", timeRemaining: nil)
        ))
    }

    @Test("Never reports more than 100%")
    func clampsProgress() {
        #expect(YtDlpOutputLine("progress=250") == .progress(DownloadProgress(fraction: 1, speed: nil, timeRemaining: nil)))
    }

    @Test("Reads the video title")
    func parsesTitle() {
        #expect(YtDlpOutputLine("title=Me at the zoo") == .title("Me at the zoo"))
    }

    @Test("Reads the final file path, including spaces")
    func parsesFile() {
        #expect(YtDlpOutputLine("file=/tmp/Me at the zoo.mp4") == .file(URL(filePath: "/tmp/Me at the zoo.mp4")))
    }

    @Test("Reads subtitle paths, dropping a temporary suffix")
    func parsesTranscript() {
        #expect(
            YtDlpOutputLine("[info] Writing video subtitles to: /tmp/Me at the zoo.en.vtt")
                == .transcript(URL(filePath: "/tmp/Me at the zoo.en.vtt"))
        )
        #expect(
            YtDlpOutputLine("[info] Writing video subtitles to: /tmp/clip.en.vtt.part")
                == .transcript(URL(filePath: "/tmp/clip.en.vtt"))
        )
    }

    @Test("Reads a subtitle failure that yt-dlp reports only as a warning")
    func parsesTranscriptWarning() {
        #expect(
            YtDlpOutputLine("WARNING: Unable to download video subtitles for 'en': HTTP Error 429: Too Many Requests")
                == .transcriptWarning("Unable to download video subtitles for 'en': HTTP Error 429: Too Many Requests")
        )
    }

    @Test("Reads error messages without their prefix")
    func parsesError() {
        #expect(
            YtDlpOutputLine("ERROR: [youtube] abc: This video is unavailable")
                == .error("[youtube] abc: This video is unavailable")
        )
    }

    @Test("Ignores everything else", arguments: ["progress=NA\tNA\tNA", "WARNING: slow", "[youtube] abc: Downloading", ""])
    func ignoresOtherLines(line: String) {
        #expect(YtDlpOutputLine(line) == .other)
    }
}
