//
//  youtubedownloadApp.swift
//  youtubedownload
//
//  Created by Juan Casanueva on 01/11/2026.
//

import AppKit
import SwiftUI

/// The app lives only in the menu bar (`LSUIElement = YES`).
@main
struct youtubedownloadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // An empty Settings scene is the only scene, so no window opens at launch.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
    }
}
