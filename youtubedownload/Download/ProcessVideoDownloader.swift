import Foundation

/// Runs the yt-dlp executable as a child process.
nonisolated struct ProcessVideoDownloader: VideoDownloading {
    /// Apps launched from Finder get a minimal PATH, so common install locations are listed explicitly.
    static let defaultSearchDirectories: [URL] = [
        URL(filePath: "/opt/homebrew/bin"),
        URL(filePath: "/usr/local/bin"),
        URL(filePath: "/opt/local/bin"),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin"),
    ]

    let searchDirectories: [URL]

    init(searchDirectories: [URL] = Self.defaultSearchDirectories) {
        self.searchDirectories = searchDirectories
    }

    func download(_ request: DownloadRequest) -> AsyncThrowingStream<DownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    try await perform(request, reportingTo: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func playlistEntries(of playlist: YouTubePlaylistURL) async throws -> [PlaylistEntry] {
        var entries: [PlaylistEntry] = []
        var lastError: String?

        let status = try await run(arguments: YtDlpCommand.playlistArguments(for: playlist)) { line in
            if case .error(let message) = YtDlpOutputLine(line) { lastError = message }
            if let entry = Self.playlistEntry(from: line) { entries.append(entry) }
        }

        if status != 0, entries.isEmpty {
            throw DownloadError.failed(lastError ?? Self.exitMessage(status))
        }
        return entries
    }

    /// The version of the copy that runs, or `nil` if it's missing or broken.
    func installedVersion() async -> String? {
        var version: String?
        let status = try? await run(arguments: ["--version"]) { line in
            if version == nil, let parsed = YtDlpVersion(line) { version = parsed.text }
        }
        return status == 0 ? version : nil
    }

    // MARK: - Passes

    private func perform(
        _ request: DownloadRequest,
        reportingTo continuation: AsyncThrowingStream<DownloadEvent, Error>.Continuation
    ) async throws {
        let file = try await downloadVideo(request, reportingTo: continuation)
        if let languages = request.transcriptLanguages {
            try Task.checkCancellation()
            continuation.yield(.fetchingTranscripts)
            await fetchTranscripts(request, languages: languages, videoFile: file, reportingTo: continuation)
        }
        try Task.checkCancellation()
        continuation.yield(.finished(file ?? request.destination))
    }

    private func downloadVideo(
        _ request: DownloadRequest,
        reportingTo continuation: AsyncThrowingStream<DownloadEvent, Error>.Continuation
    ) async throws -> URL? {
        var file: URL?
        var lastError: String?
        let arguments = YtDlpCommand.videoArguments(for: request.video, destination: request.destination, quality: request.quality)

        let status = try await run(arguments: arguments) { line in
            switch YtDlpOutputLine(line) {
            case .title(let title): continuation.yield(.title(title))
            case .progress(let progress): continuation.yield(.progress(progress))
            case .file(let url): file = url
            case .error(let message): lastError = message
            case .transcript, .transcriptWarning, .other: break
            }
        }

        guard status == 0 else {
            throw DownloadError.failed(withUpdateHint(lastError ?? Self.exitMessage(status)))
        }
        return file
    }

    /// Never throws: the video is already saved, so a failure here is only reported.
    private func fetchTranscripts(
        _ request: DownloadRequest,
        languages: String,
        videoFile: URL?,
        reportingTo continuation: AsyncThrowingStream<DownloadEvent, Error>.Continuation
    ) async {
        var written: [URL] = []
        var lastError: String?
        var lastWarning: String?
        let arguments = YtDlpCommand.transcriptArguments(
            for: request.video,
            destination: request.destination,
            languages: languages,
            videoFile: videoFile
        )

        let status: Int32
        do {
            status = try await run(arguments: arguments) { line in
                switch YtDlpOutputLine(line) {
                case .transcript(let url): written.append(url)
                case .transcriptWarning(let message): lastWarning = message
                case .error(let message): lastError = message
                default: break
                }
            }
        } catch {
            continuation.yield(.transcriptsFailed(error.localizedDescription))
            return
        }

        // yt-dlp logs each path before fetching it, so a refused track has a line but no file.
        let saved = written.filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
        saved.forEach { continuation.yield(.transcript($0)) }

        // One saved language is a success. Only an empty result is worth reporting.
        guard saved.isEmpty else { return }
        if status != 0 {
            continuation.yield(.transcriptsFailed(lastError ?? Self.exitMessage(status)))
        } else if let lastWarning {
            continuation.yield(.transcriptsFailed(lastWarning))
        }
    }

    // MARK: - Process

    /// Runs yt-dlp to completion, stopping it if the current task is cancelled.
    private func run(arguments: [String], onLine: (String) -> Void) async throws -> Int32 {
        guard let executable = locateExecutable() else {
            throw DownloadError.toolNotFound
        }

        let output = Pipe()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice

        // waitUntilExit() would block a cooperative thread and can hang forever there.
        let (exitStatus, exitContinuation) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }

        do {
            try process.run()
        } catch {
            throw DownloadError.failed(error.localizedDescription)
        }

        return await withTaskCancellationHandler {
            // A read error only means less output; the exit status still decides the result.
            do {
                for try await line in output.fileHandleForReading.bytes.lines {
                    onLine(line)
                }
            } catch {}
            return await exitStatus.first { _ in true } ?? -1
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    /// YouTube answers 403 to the old versions it has broken, and nothing in the error says so.
    private func withUpdateHint(_ message: String) -> String {
        guard message.contains("HTTP Error 403") else { return message }
        return "\(message). Try updating yt-dlp: \(YtDlpStatus.updateCommand(for: locateExecutable()))"
    }

    func locateExecutable() -> URL? {
        searchDirectories
            .map { $0.appending(path: "yt-dlp") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }

    /// yt-dlp needs ffmpeg and a JavaScript runtime from the same directories.
    private func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let directories = searchDirectories.map { $0.path(percentEncoded: false) }
        environment["PATH"] = (directories + [environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        return environment
    }

    private static func exitMessage(_ status: Int32) -> String {
        "yt-dlp exited with code \(status)."
    }

    /// Reads `id<TAB>title`. Anything else, such as a log line, is skipped.
    private static func playlistEntry(from line: String) -> PlaylistEntry? {
        let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
        guard fields.count == 2, let video = YouTubeURL("https://youtu.be/\(fields[0])") else {
            return nil
        }
        return PlaylistEntry(video: video, title: fields[1] == "NA" ? nil : fields[1])
    }
}
