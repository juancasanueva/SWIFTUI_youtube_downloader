import Foundation
import Observation
import ServiceManagement

nonisolated enum LoginItemStatus: Sendable, Hashable {
    case enabled
    case disabled
    /// Registered, but the user still has to allow it in System Settings › Login Items.
    case requiresApproval
    /// The system can't find the app to register.
    case notFound
}

/// Port for the app's login item.
protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// The "Launch at Login" setting. The system owns it, so it's read back from the
/// service instead of being stored. Only whether the default was applied is stored.
@MainActor
@Observable
final class LaunchAtLogin {
    private static let defaultAppliedKey = "launchAtLoginDefaultApplied"

    private(set) var status: LoginItemStatus
    /// Why the last change failed; cleared by the next successful one.
    private(set) var errorMessage: String?

    @ObservationIgnored private let service: any LoginItemService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let appURL: URL

    /// On once registered, even while waiting for the user's approval.
    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var needsApproval: Bool {
        status == .requiresApproval
    }

    init(service: any LoginItemService, defaults: UserDefaults = .standard, appURL: URL = Bundle.main.bundleURL) {
        self.service = service
        self.defaults = defaults
        self.appURL = appURL
        status = service.status
    }

    /// Turns it on once, so a later choice to turn it off sticks.
    /// Only from an installed copy: a login item registered from a build folder
    /// would point at a path that later disappears.
    func applyDefault() {
        guard !defaults.bool(forKey: Self.defaultAppliedKey), Self.isInstalled(appURL) else { return }

        if isEnabled {
            defaults.set(true, forKey: Self.defaultAppliedKey)
        } else {
            setEnabled(true)
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            errorMessage = nil
            defaults.set(true, forKey: Self.defaultAppliedKey)
        } catch {
            let action = enabled ? "on" : "off"
            errorMessage = "Couldn't turn \(action) launch at login: \(error.localizedDescription)"
        }
        status = service.status
    }

    /// Re-reads the status, which the user can change in System Settings at any time.
    func refreshStatus() {
        status = service.status
    }

    nonisolated static func isInstalled(_ appURL: URL) -> Bool {
        let path = appURL.standardizedFileURL.path(percentEncoded: false)
        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Applications", directoryHint: .isDirectory)
            .path(percentEncoded: false)
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications)
    }
}

/// The real login item, registered for this app's own bundle.
final class MainAppLoginItem: LoginItemService {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .notRegistered: .disabled
        @unknown default: .disabled
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
