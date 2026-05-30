//
//  RepoStudioApp.swift
//  RepoStudio
//
//  Created by Kryštof Sláma on 28.05.2026.
//

import AppKit
import SwiftUI

@main
struct RepoStudioApp: App {
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
