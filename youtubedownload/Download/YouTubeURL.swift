import Foundation

/// A URL proven to point at a single YouTube video.
nonisolated struct YouTubeURL: Equatable, Sendable {
    let url: URL

    private static let watchHosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"]
    private static let videoPathPrefixes: Set<String> = ["shorts", "live", "embed"]

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"

        guard
            let components = URLComponents(string: candidate),
            let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = components.host?.lowercased(),
            let url = components.url,
            Self.pointsToVideo(host: host, components: components)
        else {
            return nil
        }
        self.url = url
    }

    private static func pointsToVideo(host: String, components: URLComponents) -> Bool {
        let segments = components.path.split(separator: "/")

        if host == "youtu.be" {
            return segments.count == 1
        }
        guard watchHosts.contains(host), let first = segments.first else {
            return false
        }
        if first == "watch" {
            let videoID = components.queryItems?.first { $0.name == "v" }?.value
            return videoID?.isEmpty == false
        }
        return videoPathPrefixes.contains(String(first)) && segments.count == 2
    }
}
