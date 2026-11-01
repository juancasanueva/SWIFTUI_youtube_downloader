import SwiftUI

struct DownloadPanelView: View {
    @Bindable var queue: DownloadQueue
    let settings: SettingsStore
    let onOpenSettings: () -> Void
    let onClose: () -> Void

    @State private var listHeight: CGFloat = 0
    @FocusState private var isURLFieldFocused: Bool

    private let maxListHeight: CGFloat = 440

    var body: some View {
        VStack(alignment: .leading) {
            inputRow
            inputStatus

            ScrollView {
                lists
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .frame(height: min(listHeight, maxListHeight))
        }
        .padding()
        .frame(width: 480)
        .onAppear { isURLFieldFocused = true }
        .onExitCommand(perform: onClose)
    }

    private var inputRow: some View {
        HStack {
            TextField("YouTube video or playlist URL", text: $queue.urlDraft)
                .textFieldStyle(.roundedBorder)
                .focused($isURLFieldFocused)
                .onSubmit(submit)

            Picker("Resolution", selection: $queue.qualityChoice) {
                ForEach(QualityChoice.all) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .labelsHidden()
            .fixedSize()
            .help("Resolution. Default is \(settings.defaultVideoQuality.label), which you can change in Settings.")

            Button("Download", action: submit)
                .keyboardShortcut(.defaultAction)
                .disabled(queue.urlDraft.isEmpty)

            Button("Settings", systemImage: "gearshape", action: onOpenSettings)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Settings")
        }
    }

    @ViewBuilder
    private var inputStatus: some View {
        if let error = queue.inputError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else if queue.isReadingPlaylist {
            Text("Reading playlist…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var lists: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !queue.active.isEmpty {
                DownloadSection(title: "Active Downloads", count: queue.active.count, clearLabel: "Cancel all", clear: queue.cancelAll) {
                    ForEach(queue.active) { item in
                        ActiveDownloadRow(item: item) { queue.cancel(item.id) }
                    }
                }
            }
            if !queue.queued.isEmpty {
                DownloadSection(title: "Queue", count: queue.queued.count, clearLabel: "Clear queue", clear: queue.clearQueue) {
                    ForEach(queue.queued) { item in
                        QueuedDownloadRow(item: item) { queue.cancel(item.id) }
                    }
                }
            }
            if !queue.history.entries.isEmpty {
                DownloadSection(title: "History", count: queue.history.entries.count, clearLabel: "Clear history", clear: queue.history.clear) {
                    ForEach(queue.history.entries) { entry in
                        HistoryRow(entry: entry) {
                            queue.downloadAgain(
                                entry,
                                destination: settings.downloadFolder,
                                transcriptLanguages: settings.transcriptRequest,
                                quality: queue.qualityChoice.resolved(default: settings.defaultVideoQuality)
                            )
                        } onRemove: {
                            queue.history.remove(entry.id)
                        }
                    }
                }
            }
        }
    }

    private func submit() {
        _ = queue.submitDraft(
            destination: settings.downloadFolder,
            transcriptLanguages: settings.transcriptRequest,
            defaultQuality: settings.defaultVideoQuality
        )
    }
}
