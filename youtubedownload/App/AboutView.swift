import AppKit
import SwiftUI

struct AboutView: View {
    let info: AboutInfo

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text(info.name)
                    .font(.title2.bold())
                Text(info.versionText)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(spacing: 4) {
                Link("View on GitHub", destination: AboutInfo.repositoryURL)
                Link("Released under the MIT License", destination: AboutInfo.licenseURL)
            }
            .font(.callout)
        }
        .padding(24)
        .frame(width: 280)
    }
}

#Preview {
    AboutView(info: AboutInfo(infoDictionary: ["CFBundleShortVersionString": "1.0.6", "CFBundleVersion": "1"]))
}
