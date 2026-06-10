//
//  RepoStudioApp.swift
//  RepoStudio
//
//  Created by Kryštof Sláma on 28.05.2026.
//

import AppKit
import SwiftUI

@MainActor
final class RepoStudioAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            Self.removeDuplicateSettingsMenuItems(in: NSApp.mainMenu)
        }
    }

    static func removeDuplicateSettingsMenuItems(in mainMenu: NSMenu?) {
        guard let appMenu = mainMenu?.items.first?.submenu else {
            return
        }

        let settingsItemIndexes = appMenu.items.indices.filter { index in
            let title = appMenu.items[index].title
            return title == "Settings..." || title == "Preferences..."
        }

        guard settingsItemIndexes.count > 1 else {
            return
        }

        for index in settingsItemIndexes.dropLast().reversed() {
            appMenu.removeItem(at: index)
        }
    }
}

@main
struct RepoStudioApp: App {
    @NSApplicationDelegateAdaptor(RepoStudioAppDelegate.self) private var appDelegate

    init() {
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    var body: some Scene {
        WindowGroup("RepoStudio") {
            WorkspaceView()
        }
        .commands {
            DashboardCommands()
        }
    }
}
