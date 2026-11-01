import Foundation

nonisolated enum VideoQuality: String, CaseIterable, Identifiable, Sendable {
    case best
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"

    var id: Self { self }

    var label: String {
        self == .best ? "Best" : rawValue
    }
}

nonisolated struct DownloadRequest: Equatable, Sendable {
    let video: YouTubeURL
    let destination: URL
    /// Comma-separated language codes, or `nil` to skip transcripts.
    let transcriptLanguages: String?
    let quality: VideoQuality
}

nonisolated struct DownloadProgress: Equatable, Sendable {
    let fraction: Double
    let speed: String?
    let timeRemaining: String?
}

nonisolated enum DownloadEvent: Equatable, Sendable {
    case title(String)
    case progress(DownloadProgress)
    case fetchingTranscripts
    case transcript(URL)
    /// The video is still good; only its transcripts failed.
    case transcriptsFailed(String)
    /// Always the last event of a successful download.
    case finished(URL)
}

nonisolated struct PlaylistEntry: Equatable, Sendable {
    let video: YouTubeURL
    let title: String?
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

/// Port for whatever performs the downloads. Cancelling the consumer stops the work.
nonisolated protocol VideoDownloading: Sendable {
    func download(_ request: DownloadRequest) -> AsyncThrowingStream<DownloadEvent, Error>
    func playlistEntries(of playlist: YouTubePlaylistURL) async throws -> [PlaylistEntry]
}
