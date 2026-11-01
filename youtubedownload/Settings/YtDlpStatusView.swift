import AppKit
import SwiftUI

struct YtDlpStatusView: View {
    let status: YtDlpStatus

    var body: some View {
        if let location = status.location {
            installedRow(location: location)

            if status.isOutdated {
                instructions(
                    message: "This version is more than 90 days old, and YouTube may refuse its downloads. Update it by running this in Terminal:",
                    command: status.updateCommand
                )
            }
        } else {
            LabeledContent("yt-dlp") {
                Label("Not installed", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            instructions(
                message: "Downloads need yt-dlp, and ffmpeg for resolutions above 360p. Install them with Homebrew by running this in Terminal:",
                command: YtDlpStatus.installCommand,
                offersHomebrewLink: true
            )
        }
    }

    private func installedRow(location: URL) -> some View {
        LabeledContent("yt-dlp") {
            Group {
                if status.isOutdated {
                    Label(installedText("Out of date"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Label(installedText("Installed"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .help(location.path(percentEncoded: false))
        }
    }

    private func installedText(_ state: String) -> String {
        status.version.map { "\(state), \($0.text)" } ?? state
    }

    private func instructions(message: String, command: String, offersHomebrewLink: Bool = false) -> some View {
        VStack(alignment: .leading) {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(command)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Copy") { copy(command) }
            }

            if offersHomebrewLink {
                Link("Don't have Homebrew? Get it at brew.sh", destination: URL(string: "https://brew.sh")!)
                    .font(.caption)
            }
        }
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
