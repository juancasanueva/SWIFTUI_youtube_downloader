import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let launchAtLogin: LaunchAtLogin
    let ytDlp: YtDlpStatus
    let updater: (any AppUpdating)?

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.setEnabled($0) })
    }

    var body: some View {
        Form {
            Section {
                YtDlpStatusView(status: ytDlp)
            }

            Section {
                Toggle("Launch at Login", isOn: launchAtLoginBinding)

                if launchAtLogin.needsApproval {
                    LabeledContent("Allow it in System Settings to take effect.") {
                        Button("Open Login Items") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                    .font(.caption)
                }
                if let error = launchAtLogin.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            LabeledContent("Download folder") {
                HStack {
                    Text(settings.downloadFolder.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(settings.downloadFolder.path(percentEncoded: false))
                    Button("Choose…", action: chooseFolder)
                }
            }

            if let updater {
                UpdatesSection(updater: updater)
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
        .onAppear(perform: refreshSystemState)
        // Either can change while the app is in the background, such as installing yt-dlp in Terminal.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSystemState()
        }
    }

    private func refreshSystemState() {
        launchAtLogin.refreshStatus()
        ytDlp.refresh()
        Task { await ytDlp.refreshVersion() }
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
