import Foundation

/// What the About window shows, read from the app bundle.
nonisolated struct AboutInfo: Equatable, Sendable {
    static let repositoryURL = URL(string: "https://github.com/juancasanueva/SWIFTUI_youtube_downloader")!
    static let licenseURL = repositoryURL.appending(path: "blob/main/LICENSE")

    static var current: AboutInfo {
        AboutInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }

    let name: String
    let version: String
    let build: String?

    init(infoDictionary: [String: Any]) {
        name = infoDictionary["CFBundleDisplayName"] as? String
            ?? infoDictionary["CFBundleName"] as? String
            ?? "YouTubeDownloader"
        version = infoDictionary["CFBundleShortVersionString"] as? String ?? "Unknown"
        build = infoDictionary["CFBundleVersion"] as? String
    }

    var versionText: String {
        guard let build else { return "Version \(version)" }
        return "Version \(version) (\(build))"
    }
}
