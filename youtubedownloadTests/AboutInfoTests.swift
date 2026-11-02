import Foundation
import Testing
@testable import youtubedownload

struct AboutInfoTests {
    @Test("Reads the name, version and build from the bundle")
    func readsBundleInfo() {
        let info = AboutInfo(infoDictionary: [
            "CFBundleDisplayName": "YouTubeDownloader",
            "CFBundleShortVersionString": "1.0.6",
            "CFBundleVersion": "42",
        ])
        #expect(info.name == "YouTubeDownloader")
        #expect(info.versionText == "Version 1.0.6 (42)")
    }

    @Test("Falls back to the bundle name and leaves out a missing build")
    func fallsBack() {
        let info = AboutInfo(infoDictionary: ["CFBundleName": "App", "CFBundleShortVersionString": "2.0"])
        #expect(info.name == "App")
        #expect(info.versionText == "Version 2.0")
    }

    @Test("Points at the GitHub repository and its MIT license")
    func links() {
        #expect(AboutInfo.repositoryURL.absoluteString == "https://github.com/juancasanueva/SWIFTUI_youtube_downloader")
        #expect(AboutInfo.licenseURL.absoluteString == "https://github.com/juancasanueva/SWIFTUI_youtube_downloader/blob/main/LICENSE")
    }
}
