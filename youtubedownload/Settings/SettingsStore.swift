import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private static let downloadFolderKey = "downloadFolderPath"

    var downloadFolder: URL {
        didSet {
            defaults.set(downloadFolder.path(percentEncoded: false), forKey: Self.downloadFolderKey)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let path = defaults.string(forKey: Self.downloadFolderKey) {
            downloadFolder = URL(filePath: path, directoryHint: .isDirectory)
        } else {
            downloadFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        }
    }
}
