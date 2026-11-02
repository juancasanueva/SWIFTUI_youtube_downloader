import Foundation
import Testing
@testable import youtubedownload

struct AboutInfoTests {
    @Test("Reads the version and build from the bundle")
    func readsBundleInfo() {
        let info = AboutInfo(infoDictionary: [
            "CFBundleShortVersionString": "1.0.6",
            "CFBundleVersion": "42",
        ])
        #expect(info.versionText == "Version 1.0.6 (42)")
    }

    @Test("Calls the app yt_downloader whatever the bundle name is")
    func name() {
        let info = AboutInfo(infoDictionary: ["CFBundleDisplayName": "YouTubeDownloader", "CFBundleName": "YouTubeDownloader"])
        #expect(info.name == "yt_downloader")
    }

    @Test("Leaves out a missing build")
    func leavesOutMissingBuild() {
        let info = AboutInfo(infoDictionary: ["CFBundleShortVersionString": "2.0"])
        #expect(info.versionText == "Version 2.0")
    }

    @Test("Points at the GitHub repository and its MIT license")
    func links() {
        #expect(AboutInfo.repositoryURL.absoluteString == "https://github.com/juancasanueva/SWIFTUI_youtube_downloader")
        #expect(AboutInfo.licenseURL.absoluteString == "https://github.com/juancasanueva/SWIFTUI_youtube_downloader/blob/main/LICENSE")
    }
}
