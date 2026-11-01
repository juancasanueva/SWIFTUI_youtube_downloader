import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private static let downloadFolderKey = "downloadFolderPath"
    private static let transcriptsEnabledKey = "transcriptsEnabled"
    private static let transcriptLanguagesKey = "transcriptLanguages"
    private static let defaultTranscriptLanguages = "en,es"
    /// A new key on purpose: older versions saved the panel's last pick under `videoQuality`.
    private static let defaultVideoQualityKey = "defaultVideoQuality"

    // Each setting saves only real changes. Text fields and pickers can write back the same value
    // without any edit, and saving that would freeze a default the user never chose.

    var downloadFolder: URL {
        didSet {
            guard downloadFolder != oldValue else { return }
            defaults.set(downloadFolder.path(percentEncoded: false), forKey: Self.downloadFolderKey)
        }
    }

    var transcriptsEnabled: Bool {
        didSet {
            guard transcriptsEnabled != oldValue else { return }
            defaults.set(transcriptsEnabled, forKey: Self.transcriptsEnabledKey)
        }
    }

    /// Comma-separated language codes, as typed in Settings.
    var transcriptLanguages: String {
        didSet {
            guard transcriptLanguages != oldValue else { return }
            defaults.set(transcriptLanguages, forKey: Self.transcriptLanguagesKey)
        }
    }

    /// What the panel's Default choice downloads at.
    var defaultVideoQuality: VideoQuality {
        didSet {
            guard defaultVideoQuality != oldValue else { return }
            defaults.set(defaultVideoQuality.rawValue, forKey: Self.defaultVideoQualityKey)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// The languages to fetch, or `nil` when no transcript should be fetched.
    var transcriptRequest: String? {
        guard transcriptsEnabled else { return nil }
        let languages = transcriptLanguages
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return languages.isEmpty ? nil : languages.joined(separator: ",")
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let path = defaults.string(forKey: Self.downloadFolderKey) {
            downloadFolder = URL(filePath: path, directoryHint: .isDirectory)
        } else {
            downloadFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
        transcriptsEnabled = defaults.object(forKey: Self.transcriptsEnabledKey) as? Bool ?? true
        transcriptLanguages = defaults.string(forKey: Self.transcriptLanguagesKey) ?? Self.defaultTranscriptLanguages
        defaultVideoQuality = defaults.string(forKey: Self.defaultVideoQualityKey).flatMap(VideoQuality.init) ?? .p1080
    }
}
