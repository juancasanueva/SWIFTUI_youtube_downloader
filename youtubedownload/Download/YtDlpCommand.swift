import Foundation

nonisolated enum YtDlpCommand {
    private static let outputTemplate = "%(title)s [%(id)s].%(ext)s"

    /// `--` keeps the URL from ever being read as an option.
    /// `-t mp4` prefers H.264/AAC so the result plays in QuickTime.
    static func videoArguments(for video: YouTubeURL, destination: URL) -> [String] {
        [
            "-t", "mp4",
            "--no-playlist",
            "--newline",
            "--progress",
            "--no-simulate",
            "--no-warnings",
            "--print", "before_dl:title=%(title)s",
            "--print", "after_move:file=%(filepath)s",
            "--progress-template", "download:progress=%(progress._percent)s\t%(progress._speed_str)s\t%(progress._eta_str)s",
            "-P", destination.path(percentEncoded: false),
            "-o", outputTemplate,
            "--",
            video.url.absoluteString,
        ]
    }

    /// A separate pass, because a subtitle error must not fail a good video.
    ///
    /// YouTube often answers HTTP 429 for plain auto-caption tracks such as `en`, while the same
    /// language's `en-orig` track downloads fine, so each language asks for both. Videos with only
    /// human-made subtitles have just the plain track. `--ignore-errors` stops one refused track
    /// from aborting the rest, and reports it as a warning instead.
    ///
    /// Languages need exact codes: `en.*` also matches every track auto-translated from English.
    static func transcriptArguments(for video: YouTubeURL, destination: URL, languages: String) -> [String] {
        let codes = languages.split(separator: ",").map(String.init)
        let tracks = codes.map { "\($0)-orig" } + codes

        return [
            "--no-playlist",
            "--skip-download",
            "--write-subs",
            "--write-auto-subs",
            "--ignore-errors",
            "--sub-langs", tracks.joined(separator: ","),
            "--sub-format", "vtt/best",
            "-P", destination.path(percentEncoded: false),
            "-o", outputTemplate,
            "--",
            video.url.absoluteString,
        ]
    }

    static func playlistArguments(for playlist: YouTubePlaylistURL) -> [String] {
        [
            "--yes-playlist",
            "--flat-playlist",
            "--no-warnings",
            "--print", "%(id)s\t%(title)s",
            "--",
            playlist.url.absoluteString,
        ]
    }
}

/// One line of output from a process started with `YtDlpCommand`.
nonisolated enum YtDlpOutputLine: Equatable {
    case title(String)
    case progress(DownloadProgress)
    case file(URL)
    case transcript(URL)
    case transcriptWarning(String)
    case error(String)
    case other

    init(_ line: String) {
        if let values = line.removingPrefix("progress="), let progress = DownloadProgress(templateOutput: values) {
            self = .progress(progress)
        } else if let title = line.removingPrefix("title=") {
            self = .title(title)
        } else if let path = line.removingPrefix("file=") {
            self = .file(URL(filePath: path))
        } else if let path = line.removingPrefix("[info] Writing video subtitles to: ") {
            // yt-dlp can log the temporary name before the file is finalized.
            self = .transcript(URL(filePath: path.removingSuffix(".part")))
        } else if line.hasPrefix("WARNING: Unable to download video subtitles"), let message = line.removingPrefix("WARNING: ") {
            self = .transcriptWarning(message)
        } else if let message = line.removingPrefix("ERROR: ") {
            self = .error(message)
        } else {
            self = .other
        }
    }
}

nonisolated private extension DownloadProgress {
    /// Reads `percent<TAB>speed<TAB>time remaining` from the progress template.
    init?(templateOutput: String) {
        let values = templateOutput.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard let percent = values.first.flatMap(Double.init) else { return nil }

        self.init(
            fraction: min(percent / 100, 1),
            speed: values.count > 1 ? Self.knownValue(values[1]) : nil,
            timeRemaining: values.count > 2 ? Self.knownValue(values[2]) : nil
        )
    }

    /// yt-dlp prints `Unknown…` or `NA` until it has a real value.
    private static func knownValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "NA" || trimmed.hasPrefix("Unknown") ? nil : trimmed
    }
}

nonisolated private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }

    func removingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
