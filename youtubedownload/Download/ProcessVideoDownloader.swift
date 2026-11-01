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

    func download(_ video: YouTubeURL, to destination: URL) -> AsyncThrowingStream<DownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            guard let executable = locateExecutable() else {
                continuation.finish(throwing: DownloadError.toolNotFound)
                return
            }

            let output = Pipe()
            let process = Process()
            process.executableURL = executable
            process.arguments = YtDlpCommand.arguments(for: video, destination: destination)
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

            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: DownloadError.failed(error.localizedDescription))
                return
            }

            Task.detached {
                await report(output: output, exitStatus: exitStatus, destination: destination, to: continuation)
            }
        }
    }

    private func report(
        output: Pipe,
        exitStatus: AsyncStream<Int32>,
        destination: URL,
        to continuation: AsyncThrowingStream<DownloadEvent, Error>.Continuation
    ) async {
        var file: URL?
        var lastError: String?

        do {
            for try await line in output.fileHandleForReading.bytes.lines {
                switch YtDlpOutputLine(line) {
                case .progress(let fraction): continuation.yield(.progress(fraction))
                case .file(let url): file = url
                case .error(let message): lastError = message
                case .other: break
                }
            }
        } catch {
            lastError = lastError ?? error.localizedDescription
        }

        let status = await exitStatus.first { _ in true } ?? -1

        if status == 0 {
            continuation.yield(.finished(file ?? destination))
            continuation.finish()
        } else {
            let message = lastError ?? "yt-dlp exited with code \(status)."
            continuation.finish(throwing: DownloadError.failed(message))
        }
    }

    private func locateExecutable() -> URL? {
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
}
