import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Composition root: owns the stores, the menu bar item, the hot key, and the settings window.
final class AppModel {
    private let settings = SettingsStore()
    private let queue = DownloadQueue(downloader: ProcessVideoDownloader(), history: HistoryStore())

    private lazy var settingsWindow = makeSettingsWindow()
    private var statusItem: StatusItemController?
    private var hotKey: GlobalHotKey?

    init() {
        statusItem = StatusItemController(queue: queue, settings: settings) { [weak self] in
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
        let controller = NSHostingController(rootView: SettingsView(settings: settings))
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
