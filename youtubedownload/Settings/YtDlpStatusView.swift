import AppKit
import SwiftUI

struct YtDlpStatusView: View {
    let status: YtDlpStatus

    var body: some View {
        if let location = status.location {
            LabeledContent("yt-dlp") {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help(location.path(percentEncoded: false))
            }
        } else {
            LabeledContent("yt-dlp") {
                Label("Not installed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading) {
                Text("Downloads need yt-dlp, and ffmpeg for resolutions above 360p. Install them with Homebrew by running this in Terminal:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text(YtDlpStatus.installCommand)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    Spacer()
                    Button("Copy", action: copyCommand)
                }

                Link("Don't have Homebrew? Get it at brew.sh", destination: URL(string: "https://brew.sh")!)
                    .font(.caption)
            }
        }
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(YtDlpStatus.installCommand, forType: .string)
    }
}
