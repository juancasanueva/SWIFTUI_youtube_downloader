import Foundation

/// A single YouTube video, reduced to its canonical watch URL so that nothing
/// from the typed text other than the video ID ever reaches yt-dlp.
nonisolated struct YouTubeURL: Equatable, Sendable {
    let url: URL

    private static let watchHosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"]
    private static let videoPathPrefixes: Set<String> = ["shorts", "live", "embed"]
    /// YouTube's placeholder for "the playlist in the query", which yt-dlp expands in full.
    private static let playlistPlaceholder = "videoseries"
    private static let videoIDCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    )

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"

        guard
            let components = URLComponents(string: candidate),
            let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
            components.user == nil, components.password == nil, components.port == nil,
            let host = components.host?.lowercased(),
            let videoID = Self.videoID(host: host, components: components),
            Self.isValidVideoID(videoID),
            let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)")
        else {
            return nil
        }
        self.url = url
    }

    private static func videoID(host: String, components: URLComponents) -> String? {
        let segments = components.path.split(separator: "/").map(String.init)

        if host == "youtu.be" {
            return segments.count == 1 ? segments[0] : nil
        }
        guard watchHosts.contains(host) else {
            return nil
        }
        if segments == ["watch"] {
            return components.queryItems?.first { $0.name == "v" }?.value
        }
        if segments.count == 2, videoPathPrefixes.contains(segments[0]) {
            return segments[1]
        }
        return nil
    }

    private static func isValidVideoID(_ videoID: String) -> Bool {
        !videoID.isEmpty
            && videoID != playlistPlaceholder
            && videoID.unicodeScalars.allSatisfy(videoIDCharacters.contains)
    }
}
