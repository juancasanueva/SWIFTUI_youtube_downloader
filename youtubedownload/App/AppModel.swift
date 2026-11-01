import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Composition root: owns the stores, the menu bar item, the hot key, and the settings window.
final class AppModel {
    private let settings = SettingsStore()
    private let queue = DownloadQueue(downloader: ProcessVideoDownloader(), history: HistoryStore())

    private let launchAtLogin = LaunchAtLogin(service: MainAppLoginItem())
    private let ytDlp = YtDlpStatus(locate: ProcessVideoDownloader().locateExecutable)
    /// `nil` in the unit-test host, which must never reach Sparkle or the network.
    private let updater: (any AppUpdating)? = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        ? SparkleUpdateChecker(automaticChecks: AutomaticUpdateChecks())
        : nil

    private lazy var settingsWindow = makeSettingsWindow()
    private var statusItem: StatusItemController?
    private var hotKey: GlobalHotKey?

    init() {
        launchAtLogin.applyDefault()
        statusItem = StatusItemController(queue: queue, settings: settings, updater: updater) { [weak self] in
            self?.showSettings()
        }
        hotKey = GlobalHotKey(keyCode: kVK_ANSI_D, modifiers: optionKey | shiftKey) { [weak self] in
            self?.statusItem?.togglePanel()
        }
    }

    private func showSettings() {
        NSApp.activate()
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> NSWindow {
        let controller = NSHostingController(rootView: SettingsView(settings: settings, launchAtLogin: launchAtLogin, ytDlp: ytDlp, updater: updater))
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
