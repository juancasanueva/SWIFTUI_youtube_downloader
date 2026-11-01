import Foundation
import Testing
@testable import youtubedownload

/// Login item that records calls and can be told to fail.
private final class FakeLoginItem: LoginItemService {
    struct Failure: LocalizedError {
        var errorDescription: String? { "Operation not permitted" }
    }

    var status: LoginItemStatus
    var fails = false
    var statusAfterRegister: LoginItemStatus = .enabled
    private(set) var calls: [String] = []

    init(status: LoginItemStatus = .disabled) {
        self.status = status
    }

    func register() throws {
        calls.append("register")
        if fails { throw Failure() }
        status = statusAfterRegister
    }

    func unregister() throws {
        calls.append("unregister")
        if fails { throw Failure() }
        status = .disabled
    }
}

@MainActor
struct LaunchAtLoginTests {
    private let installedApp = URL(filePath: "/Applications/youtubedownload.app", directoryHint: .isDirectory)
    private let buildFolderApp = URL(filePath: "/Users/me/Library/Developer/Xcode/DerivedData/x/youtubedownload.app", directoryHint: .isDirectory)
    private let defaults = UserDefaults(suiteName: "LaunchAtLoginTests.\(UUID().uuidString)")!

    private func model(_ item: FakeLoginItem, appURL: URL? = nil) -> LaunchAtLogin {
        LaunchAtLogin(service: item, defaults: defaults, appURL: appURL ?? installedApp)
    }

    // MARK: - On by default

    @Test("Turns on at the first launch of an installed app")
    func turnsOnByDefault() {
        let item = FakeLoginItem()
        let launchAtLogin = model(item)

        launchAtLogin.applyDefault()

        #expect(launchAtLogin.isEnabled)
        #expect(item.calls == ["register"])
    }

    @Test("Stays off at later launches once the user turned it off")
    func respectsTurningOff() {
        let item = FakeLoginItem()
        let first = model(item)
        first.applyDefault()
        first.setEnabled(false)

        let nextLaunch = model(item)
        nextLaunch.applyDefault()

        #expect(!nextLaunch.isEnabled)
        #expect(item.calls == ["register", "unregister"])
    }

    @Test("Stays off when the user turned it off in System Settings")
    func respectsSystemSettings() {
        let item = FakeLoginItem()
        model(item).applyDefault()
        item.status = .disabled

        let nextLaunch = model(item)
        nextLaunch.applyDefault()

        #expect(!nextLaunch.isEnabled)
        #expect(item.calls == ["register"])
    }

    @Test("Leaves a build folder alone, so no login item points at a temporary path")
    func skipsBuildFolders() {
        let item = FakeLoginItem()

        model(item, appURL: buildFolderApp).applyDefault()

        #expect(item.calls.isEmpty)
    }

    @Test("Still turns on after moving from a build folder to Applications")
    func appliesAfterInstalling() {
        let item = FakeLoginItem()
        model(item, appURL: buildFolderApp).applyDefault()

        model(item).applyDefault()

        #expect(item.calls == ["register"])
    }

    @Test("A choice made before installing is kept")
    func keepsChoiceFromBuildFolder() {
        let item = FakeLoginItem()
        let fromBuildFolder = model(item, appURL: buildFolderApp)
        fromBuildFolder.setEnabled(true)
        fromBuildFolder.setEnabled(false)

        model(item).applyDefault()

        #expect(item.calls == ["register", "unregister"])
    }

    @Test("Doesn't register again when already on")
    func skipsWhenAlreadyOn() {
        let item = FakeLoginItem(status: .enabled)

        model(item).applyDefault()

        #expect(item.calls.isEmpty)
    }

    @Test("Tries again at the next launch when turning on failed")
    func retriesAfterFailure() {
        let item = FakeLoginItem()
        item.fails = true
        let first = model(item)
        first.applyDefault()
        #expect(first.errorMessage == "Couldn't turn on launch at login: Operation not permitted")

        item.fails = false
        let nextLaunch = model(item)
        nextLaunch.applyDefault()

        #expect(nextLaunch.isEnabled)
    }

    @Test("Counts both Applications folders as installed", arguments: [
        "/Applications/youtubedownload.app",
        "/Applications/Utilities/youtubedownload.app",
    ])
    func recognizesApplicationsFolder(path: String) {
        #expect(LaunchAtLogin.isInstalled(URL(filePath: path, directoryHint: .isDirectory)))
    }

    @Test("Counts the user's own Applications folder as installed")
    func recognizesUserApplicationsFolder() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(LaunchAtLogin.isInstalled(home.appending(path: "Applications/youtubedownload.app")))
    }

    @Test("Doesn't mistake similar paths for installed", arguments: [
        "/ApplicationsBackup/youtubedownload.app",
        "/tmp/Applications/youtubedownload.app",
    ])
    func rejectsOtherFolders(path: String) {
        #expect(!LaunchAtLogin.isInstalled(URL(filePath: path, directoryHint: .isDirectory)))
    }

    // MARK: - The toggle

    @Test("Reflects the status the system reports")
    func reflectsSystemStatus() {
        #expect(model(FakeLoginItem(status: .enabled)).isEnabled)
        #expect(!model(FakeLoginItem(status: .disabled)).isEnabled)
    }

    @Test("Turning on registers and turning off unregisters")
    func togglesService() {
        let item = FakeLoginItem()
        let launchAtLogin = model(item)

        launchAtLogin.setEnabled(true)
        #expect(launchAtLogin.isEnabled)

        launchAtLogin.setEnabled(false)
        #expect(!launchAtLogin.isEnabled)
        #expect(item.calls == ["register", "unregister"])
        #expect(launchAtLogin.errorMessage == nil)
    }

    @Test("Pending approval counts as on and says so")
    func handlesPendingApproval() {
        let item = FakeLoginItem()
        item.statusAfterRegister = .requiresApproval
        let launchAtLogin = model(item)

        launchAtLogin.setEnabled(true)

        #expect(launchAtLogin.isEnabled)
        #expect(launchAtLogin.needsApproval)
    }

    @Test("A failure keeps the real status and reports why, until the next success")
    func reportsFailures() {
        let item = FakeLoginItem()
        item.fails = true
        let launchAtLogin = model(item)

        launchAtLogin.setEnabled(true)
        #expect(!launchAtLogin.isEnabled)
        #expect(launchAtLogin.errorMessage == "Couldn't turn on launch at login: Operation not permitted")

        item.status = .enabled
        launchAtLogin.refreshStatus()
        launchAtLogin.setEnabled(false)
        #expect(launchAtLogin.isEnabled)
        #expect(launchAtLogin.errorMessage == "Couldn't turn off launch at login: Operation not permitted")

        item.fails = false
        launchAtLogin.setEnabled(false)
        #expect(!launchAtLogin.isEnabled)
        #expect(launchAtLogin.errorMessage == nil)
    }

    @Test("Picks up changes made in System Settings")
    func refreshesStatus() {
        let item = FakeLoginItem(status: .enabled)
        let launchAtLogin = model(item)

        item.status = .disabled
        launchAtLogin.refreshStatus()

        #expect(!launchAtLogin.isEnabled)
    }
}
