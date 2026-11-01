import AppKit
import SwiftUI

struct DownloadPanelView: View {
    let store: DownloadStore
    let settings: SettingsStore
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    @State private var urlText = ""
    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("YouTube video URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isURLFieldFocused)
                    .disabled(store.isDownloading)
                    .onSubmit(startDownload)

                if store.isDownloading {
                    Button("Cancel", action: store.cancel)
                } else {
                    Button("Download", action: startDownload)
                        .keyboardShortcut(.defaultAction)
                        .disabled(urlText.isEmpty)
                }

                Button("Settings", systemImage: "gearshape", action: onOpenSettings)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Settings")
            }

            status
        }
        .padding()
        .frame(width: 420)
        .onAppear { isURLFieldFocused = true }
        .onExitCommand(perform: onClose)
        .onChange(of: store.phase) { _, phase in
            if case .finished = phase { urlText = "" }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch store.phase {
        case .idle:
            Text("Saves to \(settings.downloadFolder.path(percentEncoded: false))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

        case .downloading(let progress):
            ProgressView(value: progress) {
                Text("Downloading…").font(.caption)
            }

        case .finished(let file):
            HStack {
                Label(file.lastPathComponent, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                }
                .controlSize(.small)
            }

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func startDownload() {
        store.start(urlText: urlText, destination: settings.downloadFolder)
    }
}
