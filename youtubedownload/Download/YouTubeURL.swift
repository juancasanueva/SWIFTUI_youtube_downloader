import Foundation

/// Rules shared by the URL types: only the ID from the typed text ever reaches yt-dlp.
nonisolated private enum YouTubeLink {
    static let watchHosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"]
    static let idCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    )

    /// Parses web URLs with no credentials or custom port, assuming https when the scheme is missing.
    static func components(of text: String) -> URLComponents? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"

        guard
            let components = URLComponents(string: candidate),
            let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
            components.user == nil, components.password == nil, components.port == nil
        else {
            return nil
        }
        return components
    }

    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy(idCharacters.contains)
    }
}

/// A single YouTube video, reduced to its canonical watch URL.
nonisolated struct YouTubeURL: Hashable, Sendable {
    let url: URL

    private static let videoPathPrefixes: Set<String> = ["shorts", "live", "embed"]
    /// YouTube's placeholder for "the playlist in the query", which yt-dlp expands in full.
    private static let playlistPlaceholder = "videoseries"

    init?(_ text: String) {
        guard
            let components = YouTubeLink.components(of: text),
            let videoID = Self.videoID(in: components),
            videoID != Self.playlistPlaceholder,
            YouTubeLink.isValidID(videoID),
            let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)")
        else {
            return nil
        }
        self.url = url
    }

    private static func videoID(in components: URLComponents) -> String? {
        let host = components.host?.lowercased() ?? ""
        let segments = components.path.split(separator: "/").map(String.init)

        if host == "youtu.be" {
            return segments.count == 1 ? segments[0] : nil
        }
        guard YouTubeLink.watchHosts.contains(host) else {
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
}

/// A YouTube playlist page, reduced to its canonical URL.
/// A watch URL that also names a playlist counts as a single video.
nonisolated struct YouTubePlaylistURL: Hashable, Sendable {
    let url: URL

    init?(_ text: String) {
        guard
            let components = YouTubeLink.components(of: text),
            let host = components.host?.lowercased(), YouTubeLink.watchHosts.contains(host),
            components.path.split(separator: "/") == ["playlist"],
            let listID = components.queryItems?.first(where: { $0.name == "list" })?.value,
            YouTubeLink.isValidID(listID),
            let url = URL(string: "https://www.youtube.com/playlist?list=\(listID)")
        else {
            return nil
        }
        self.url = url
    }
}
