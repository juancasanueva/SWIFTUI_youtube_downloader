import Foundation

nonisolated enum YtDlpCommand {
    /// The height keeps each resolution in its own file. With one shared name, asking for 720p
    /// after 1080p would find the existing file and report success without downloading anything.
    private static let videoTemplate = "%(title)s [%(id)s] %(height)sp.%(ext)s"
    private static let transcriptFallbackTemplate = "%(title)s [%(id)s].%(ext)s"

    /// `--` keeps the URL from ever being read as an option.
    static func videoArguments(for video: YouTubeURL, destination: URL, quality: VideoQuality) -> [String] {
        [
            "--merge-output-format", "mp4",
            "--remux-video", "mp4",
            "-S", quality.formatSort,
            "--no-playlist",
            "--newline",
            "--progress",
            "--no-simulate",
            "--no-warnings",
            "--print", "before_dl:title=%(title)s",
            "--print", "after_move:file=%(filepath)s",
            "--progress-template", "download:progress=%(progress._percent)s\t%(progress._speed_str)s\t%(progress._eta_str)s",
            "-P", destination.path(percentEncoded: false),
            "-o", videoTemplate,
            "--",
            video.url.absoluteString,
        ]
    }

    /// A separate pass, because a subtitle error must not fail a good video.
    ///
    /// YouTube often answers HTTP 429 for plain auto-caption tracks such as `en`, while the same
    /// language's `en-orig` track downloads fine, so each language asks for both. Videos with only
    /// human-made subtitles have just the plain track. `--ignore-errors` stops one refused track
    /// from aborting the rest, and reports it as a warning instead. Identical copies are removed
    /// after the pass.
    ///
    /// Languages need exact codes: `en.*` also matches every track auto-translated from English.
    ///
    /// Named after `videoFile`, so subtitles sit beside the video they belong to.
    static func transcriptArguments(for video: YouTubeURL, destination: URL, languages: String, videoFile: URL?) -> [String] {
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
            "-o", videoFile.map(transcriptTemplate) ?? transcriptFallbackTemplate,
            "--",
            video.url.absoluteString,
        ]
    }

    private static func transcriptTemplate(for videoFile: URL) -> String {
        let name = videoFile.deletingPathExtension().lastPathComponent
        return "\(name.replacingOccurrences(of: "%", with: "%%")).%(ext)s"
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

nonisolated private extension VideoQuality {
    /// A capped resolution comes first so it's always honored, then H.264/AAC so the result plays
    /// in QuickTime. YouTube generally has no H.264 above 1080p, so Best drops that preference.
    var formatSort: String {
        switch self {
        case .best: "res,fps,hdr:12,acodec:aac"
        case .p1080: Self.cappedSort(height: 1080)
        case .p720: Self.cappedSort(height: 720)
        case .p480: Self.cappedSort(height: 480)
        }
    }

    private static func cappedSort(height: Int) -> String {
        "res:\(height),vcodec:h264,lang,quality,fps,hdr:12,acodec:aac"
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
