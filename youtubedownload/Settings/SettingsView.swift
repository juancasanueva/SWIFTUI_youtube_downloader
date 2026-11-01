import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            LabeledContent("Download folder") {
                HStack {
                    Text(settings.downloadFolder.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(settings.downloadFolder.path(percentEncoded: false))
                    Button("Choose…", action: chooseFolder)
                }
            }

            Section {
                Toggle("Download transcripts", isOn: $settings.transcriptsEnabled)
                TextField("Languages", text: $settings.transcriptLanguages, prompt: Text("en,es"))
                    .disabled(!settings.transcriptsEnabled)
            } footer: {
                Text("Exact language codes separated by commas. Saved as subtitle files next to each video.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.downloadFolder
        panel.prompt = "Choose"

        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadFolder = url
        }
    }
}
