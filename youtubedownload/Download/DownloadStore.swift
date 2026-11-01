import Foundation
import Observation

@MainActor
@Observable
final class DownloadStore {
    enum Phase: Equatable {
        case idle
        case downloading(progress: Double?)
        case finished(URL)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var currentDownload: Task<Void, Never>?

    @ObservationIgnored private let downloader: any VideoDownloading

    var isDownloading: Bool {
        if case .downloading = phase { true } else { false }
    }

    init(downloader: any VideoDownloading) {
        self.downloader = downloader
    }

    func start(urlText: String, destination: URL) {
        guard !isDownloading else { return }
        guard let video = YouTubeURL(urlText) else {
            phase = .failed("Enter a valid YouTube video URL.")
            return
        }

        phase = .downloading(progress: nil)
        let events = downloader.download(video, to: destination)
        currentDownload = Task { await consume(events) }
    }

    func cancel() {
        currentDownload?.cancel()
    }

    /// Forgets a result the user has seen. A running download is left alone.
    func clearResult() {
        if !isDownloading { phase = .idle }
    }

    private func consume(_ events: AsyncThrowingStream<DownloadEvent, Error>) async {
        do {
            for try await event in events {
                switch event {
                case .progress(let fraction): phase = .downloading(progress: fraction)
                case .finished(let file): phase = .finished(file)
                }
            }
            if Task.isCancelled { phase = .idle }
        } catch {
            phase = Task.isCancelled ? .idle : .failed(error.localizedDescription)
        }
    }
}
