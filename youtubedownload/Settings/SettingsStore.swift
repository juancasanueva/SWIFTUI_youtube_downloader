import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private static let downloadFolderKey = "downloadFolderPath"
    private static let transcriptsEnabledKey = "transcriptsEnabled"
    private static let transcriptLanguagesKey = "transcriptLanguages"
    private static let defaultTranscriptLanguages = "en,es"

    var downloadFolder: URL {
        didSet {
            defaults.set(downloadFolder.path(percentEncoded: false), forKey: Self.downloadFolderKey)
        }
    }

    var transcriptsEnabled: Bool {
        didSet {
            defaults.set(transcriptsEnabled, forKey: Self.transcriptsEnabledKey)
        }
    }

    /// Comma-separated language codes, as typed in Settings.
    var transcriptLanguages: String {
        didSet {
            defaults.set(transcriptLanguages, forKey: Self.transcriptLanguagesKey)
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
    }
}
