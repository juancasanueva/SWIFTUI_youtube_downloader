import AppKit
import SwiftUI

struct DownloadSection<Content: View>: View {
    let title: String
    let count: Int
    let clearLabel: String
    let clear: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(title) (\(count))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(clearLabel, systemImage: "xmark.circle", action: clear)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help(clearLabel)
            }
            content
        }
    }
}

struct ActiveDownloadRow: View {
    let item: DownloadQueue.Item
    let onCancel: () -> Void

    private var title: String {
        item.title ?? item.video.url.absoluteString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RowHeader(title: title, actionLabel: "Cancel download", action: onCancel)

            if item.isFetchingTranscripts {
                ProgressView { Text(title) }
                    .progressViewStyle(.linear)
                    .labelsHidden()
            } else {
                ProgressView(value: item.progress?.fraction) { Text(title) }
                    .progressViewStyle(.linear)
                    .labelsHidden()
            }

            HStack {
                Text(leadingStatus)
                Spacer()
                if !item.isFetchingTranscripts, let remaining = item.progress?.timeRemaining {
                    Text("Time remaining \(remaining)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var leadingStatus: String {
        if item.isFetchingTranscripts { return "Fetching transcript…" }
        return item.progress?.speed ?? "Starting…"
    }
}

struct QueuedDownloadRow: View {
    let item: DownloadQueue.Item
    let onRemove: () -> Void

    var body: some View {
        RowHeader(title: item.title ?? item.video.url.absoluteString, actionLabel: "Remove from queue", action: onRemove)
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    let onDownloadAgain: () -> Void
    let onRemove: () -> Void

    private var title: String {
        entry.title ?? entry.video.absoluteString
    }

    /// The saved video, when it's still where it was downloaded to.
    private var availableFile: URL? {
        guard case .completed(let file, _, _) = entry.outcome else { return nil }
        return FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) ? file : nil
    }

    private var transcripts: [URL] {
        guard case .completed(_, let transcripts, _) = entry.outcome else { return [] }
        return transcripts.filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    var body: some View {
        HStack {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(title)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .help(caption)
            }

            Spacer()

            actions
        }
    }

    private var statusIcon: some View {
        Group {
            if case .failed = entry.outcome {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            } else if availableFile == nil {
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .accessibilityHidden(true)
    }

    private var caption: String {
        switch entry.outcome {
        case .failed(let message):
            return message
        case .completed(_, _, let transcriptError):
            guard availableFile != nil else { return "File not found" }
            if !transcripts.isEmpty { return "Completed, with transcript" }
            return transcriptError == nil ? "Completed" : "Completed, transcript failed: \(transcriptError ?? "")"
        }
    }

    private var actions: some View {
        HStack {
            if let file = availableFile {
                iconButton("Play", systemImage: "play.circle") { NSWorkspace.shared.open(file) }
                iconButton("Show in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                }
            } else {
                iconButton("Download again", systemImage: "arrow.clockwise", action: onDownloadAgain)
            }
            if let transcript = transcripts.first {
                iconButton("Open transcript", systemImage: "doc.text") { NSWorkspace.shared.open(transcript) }
            }
            iconButton("Remove from history", systemImage: "xmark", action: onRemove)
        }
    }

    private func iconButton(_ label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(label, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(label)
    }
}

private struct RowHeader: View {
    let title: String
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(title)
            Spacer()
            Button(actionLabel, systemImage: "xmark", action: action)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(actionLabel)
        }
    }
}
