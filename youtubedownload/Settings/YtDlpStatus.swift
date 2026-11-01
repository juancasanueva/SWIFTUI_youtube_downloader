import Foundation
import Observation

/// Whether yt-dlp can be found, using the same lookup as the downloader.
@MainActor
@Observable
final class YtDlpStatus {
    /// Includes ffmpeg because Homebrew's yt-dlp doesn't bring it, and without it
    /// yt-dlp can't merge video and audio, so it silently falls back to about 360p.
    nonisolated static let installCommand = "brew install yt-dlp ffmpeg"

    private(set) var location: URL?

    @ObservationIgnored private let locate: () -> URL?

    var isInstalled: Bool {
        location != nil
    }

    init(locate: @escaping () -> URL?) {
        self.locate = locate
        location = locate()
    }

    func refresh() {
        location = locate()
    }
}
