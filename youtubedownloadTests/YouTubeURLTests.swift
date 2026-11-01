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

struct YtDlpCommandTests {
    @Test("Builds arguments that download one mp4 into the destination")
    func buildsArguments() throws {
        let video = try #require(YouTubeURL("https://youtu.be/abc"))
        let arguments = YtDlpCommand.arguments(
            for: video,
            destination: URL(filePath: "/tmp/My Videos", directoryHint: .isDirectory)
        )

        #expect(arguments == [
            "-t", "mp4",
            "--no-playlist",
            "--newline",
            "--progress",
            "--no-simulate",
            "--print", "after_move:file=%(filepath)s",
            "--progress-template", "download:progress=%(progress._percent)s",
            "-P", "/tmp/My Videos/",
            "-o", "%(title)s [%(id)s].%(ext)s",
            "--",
            "https://www.youtube.com/watch?v=abc",
        ])
    }
}

struct YtDlpOutputLineTests {
    @Test("Reads progress as a 0...1 fraction")
    func parsesProgress() {
        #expect(YtDlpOutputLine("progress=25.5") == .progress(0.255))
    }

    @Test("Reads the final file path, including spaces")
    func parsesFile() {
        #expect(YtDlpOutputLine("file=/tmp/Me at the zoo.mp4") == .file(URL(filePath: "/tmp/Me at the zoo.mp4")))
    }

    @Test("Reads error messages without their prefix")
    func parsesError() {
        #expect(
            YtDlpOutputLine("ERROR: [youtube] abc: This video is unavailable")
                == .error("[youtube] abc: This video is unavailable")
        )
    }

    @Test("Ignores everything else", arguments: ["progress=NA", "WARNING: slow", "[youtube] abc: Downloading", ""])
    func ignoresOtherLines(line: String) {
        #expect(YtDlpOutputLine(line) == .other)
    }
}
