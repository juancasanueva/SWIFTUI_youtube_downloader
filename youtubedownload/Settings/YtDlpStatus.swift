import Foundation
import Observation

/// A yt-dlp release, which is named after its date.
nonisolated struct YtDlpVersion: Equatable, Sendable {
    /// yt-dlp warns at the same age, because YouTube keeps breaking old versions.
    private static let maximumAgeInDays = 90

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    let text: String
    let released: Date

    init?(_ text: String) {
        // Nightly builds add a fourth part with the time.
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").map(String.init)
        guard
            parts.count >= 3,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
            case let components = DateComponents(calendar: Self.calendar, year: year, month: month, day: day),
            components.isValidDate,
            let released = components.date
        else {
            return nil
        }
        self.text = parts.prefix(3).joined(separator: ".")
        self.released = released
    }

    func isOutdated(at now: Date) -> Bool {
        let age = Self.calendar.dateComponents([.day], from: released, to: now).day ?? 0
        return age > Self.maximumAgeInDays
    }
}

/// Whether yt-dlp can be found, using the same lookup as the downloader, and whether it's too old.
@MainActor
@Observable
final class YtDlpStatus {
    /// Includes ffmpeg because Homebrew's yt-dlp doesn't bring it, and without it
    /// yt-dlp can't merge video and audio, so it silently falls back to about 360p.
    nonisolated static let installCommand = "brew install yt-dlp ffmpeg"

    private(set) var location: URL?
    private(set) var version: YtDlpVersion?

    @ObservationIgnored private let locate: () -> URL?
    @ObservationIgnored private let readVersion: () async -> String?
    @ObservationIgnored private let now: () -> Date

    var isInstalled: Bool {
        location != nil
    }

    /// Stays false while the version is unknown, so a failed read never raises a false alarm.
    var isOutdated: Bool {
        version?.isOutdated(at: now()) ?? false
    }

    var updateCommand: String {
        Self.updateCommand(for: location)
    }

    init(
        locate: @escaping () -> URL?,
        readVersion: @escaping () async -> String? = { nil },
        now: @escaping () -> Date = { .now }
    ) {
        self.locate = locate
        self.readVersion = readVersion
        self.now = now
        location = locate()
    }

    func refresh() {
        location = locate()
        if location == nil { version = nil }
    }

    /// Separate from `refresh` because it starts a process, which takes a moment.
    func refreshVersion() async {
        guard location != nil else {
            version = nil
            return
        }
        version = await readVersion().flatMap(YtDlpVersion.init)
    }

    /// The command that updates the copy that actually runs. `brew upgrade` doesn't touch a copy
    /// installed another way, such as with pip, so that one gets replaced by Homebrew's.
    nonisolated static func updateCommand(for location: URL?) -> String {
        let isHomebrewCopy = location?.resolvingSymlinksInPath().path(percentEncoded: false).contains("/Cellar/") ?? false
        return isHomebrewCopy ? "brew upgrade yt-dlp" : "brew install yt-dlp && brew link --overwrite yt-dlp"
    }
}
