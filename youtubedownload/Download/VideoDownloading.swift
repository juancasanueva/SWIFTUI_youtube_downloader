import Foundation

nonisolated enum DownloadEvent: Equatable, Sendable {
    case progress(Double)
    case finished(URL)
}

nonisolated enum DownloadError: LocalizedError, Equatable {
    case toolNotFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .toolNotFound:
            "yt-dlp is not installed. Install it with: brew install yt-dlp"
        case .failed(let message):
            message
        }
    }
}

/// Port for whatever performs the download. Cancelling the consumer stops the download.
nonisolated protocol VideoDownloading: Sendable {
    func download(_ video: YouTubeURL, to destination: URL) -> AsyncThrowingStream<DownloadEvent, Error>
}
