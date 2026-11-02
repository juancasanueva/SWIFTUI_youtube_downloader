import AppKit
import SwiftUI

/// What the menu bar button shows for the current download state.
nonisolated struct StatusItemLook: Equatable {
    let symbolName: String
    let accessibilityLabel: String

    init(isDownloading: Bool) {
        symbolName = isDownloading ? "arrow.down.circle.fill" : "arrow.down.circle"
        accessibilityLabel = isDownloading ? "YouTube Downloader, downloading" : "YouTube Downloader"
    }
}

/// Owns the menu bar button and the popover that points at it.
/// A left click toggles the popover; a right click shows the context menu.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let queue: DownloadQueue
    private let settings: SettingsStore
    /// `nil` in the unit-test host; the menu item is then disabled.
    private let updater: (any AppUpdating)?
    private let openSettings: () -> Void
    private let openAbout: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var outsideClickMonitor: Any?

    var isPanelOpen: Bool {
        popover.isShown
    }

    init(queue: DownloadQueue, settings: SettingsStore, updater: (any AppUpdating)?, openSettings: @escaping () -> Void, openAbout: @escaping () -> Void) {
        self.queue = queue
        self.settings = settings
        self.updater = updater
        self.openSettings = openSettings
        self.openAbout = openAbout
        super.init()

        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // Not `.transient`: it closes the popover at once when a global shortcut opens it.
        // Clicks outside are handled by `outsideClickMonitor` instead.
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        observeQueue()
    }

    isolated deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func togglePanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // A fresh view refocuses the field on every opening. What was typed lives in the queue.
            popover.contentViewController = makePanelContent()
            // A menu bar app is not active, and the text field needs key status.
            // A global shortcut brings no activation of its own, so it has to be forced.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        popover.contentViewController?.view.window?.makeKey()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        queue.clearInputError()
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    private func makePanelContent() -> NSViewController {
        let view = DownloadPanelView(
            queue: queue,
            settings: settings,
            onOpenSettings: { [weak self] in self?.showSettingsFromPanel() },
            onClose: { [weak self] in self?.popover.performClose(nil) }
        )
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        return controller
    }

    private func showSettingsFromPanel() {
        popover.performClose(nil)
        openSettings()
    }

    /// Redraws the button and re-arms itself for the next change.
    private func observeQueue() {
        let isBusy = withObservationTracking {
            queue.isBusy
        } onChange: { [weak self] in
            // Called before the change lands; read the new value on the next turn.
            Task { @MainActor in self?.observeQueue() }
        }

        let look = StatusItemLook(isDownloading: isBusy)
        statusItem.button?.image = NSImage(
            systemSymbolName: look.symbolName,
            accessibilityDescription: look.accessibilityLabel
        )
        statusItem.button?.toolTip = look.accessibilityLabel
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    /// Attaches the menu, triggers the button, then detaches it,
    /// so the next left click reaches `handleClick` instead of opening the menu.
    private func showContextMenu() {
        if popover.isShown { popover.performClose(nil) }
        statusItem.menu = makeContextMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let aboutItem = NSMenuItem(title: "About \(AboutInfo.current.name)", action: #selector(performOpenAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(performCheckForUpdates), keyEquivalent: "")
        updatesItem.target = self
        updatesItem.isEnabled = UpdateCommandEnablement.isEnabled(canCheckForUpdates: updater?.canCheckForUpdates ?? false)
        menu.addItem(updatesItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(performOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(performQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    /// Sparkle shows its own window, so the panel gets out of the way, and a menu bar
    /// app has to come forward or that window opens behind whatever is in front.
    @objc private func performCheckForUpdates() {
        if popover.isShown { popover.performClose(nil) }
        NSApp.activate(ignoringOtherApps: true)
        updater?.checkForUpdates()
    }

    @objc private func performOpenAbout() {
        if popover.isShown { popover.performClose(nil) }
        openAbout()
    }

    @objc private func performOpenSettings() {
        openSettings()
    }

    @objc private func performQuit() {
        NSApp.terminate(nil)
    }
}
