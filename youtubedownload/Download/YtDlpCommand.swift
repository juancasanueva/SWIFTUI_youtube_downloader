import Foundation

nonisolated enum YtDlpCommand {
    /// `--` keeps the URL from ever being read as an option.
    /// `-t mp4` prefers H.264/AAC so the result plays in QuickTime.
    static func arguments(for video: YouTubeURL, destination: URL) -> [String] {
        [
            "-t", "mp4",
            "--no-playlist",
            "--newline",
            "--progress",
            "--no-simulate",
            "--print", "after_move:file=%(filepath)s",
            "--progress-template", "download:progress=%(progress._percent)s",
            "-P", destination.path(percentEncoded: false),
            "-o", "%(title)s [%(id)s].%(ext)s",
            "--",
            video.url.absoluteString,
        ]
    }
}

/// One line of output from a process started with `YtDlpCommand.arguments`.
nonisolated enum YtDlpOutputLine: Equatable {
    case progress(Double)
    case file(URL)
    case error(String)
    case other

    init(_ line: String) {
        if let value = line.removingPrefix("progress="), let percent = Double(value) {
            self = .progress(percent / 100)
        } else if let path = line.removingPrefix("file=") {
            self = .file(URL(filePath: path))
        } else if let message = line.removingPrefix("ERROR: ") {
            self = .error(message)
        } else {
            self = .other
        }
    }
}

nonisolated private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
