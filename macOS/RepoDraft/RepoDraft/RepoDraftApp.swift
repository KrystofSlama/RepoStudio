//
//  RepoDraftApp.swift
//  RepoDraft
//
//  Created by Kryštof Sláma on 28.05.2026.
//

import AppKit
import SwiftUI

@main
struct RepoDraftApp: App {
    init() {
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    var body: some Scene {
        WindowGroup("RepoDraft") {
            WorkspaceView()
        }
        .commands {
            DashboardCommands()
        }
    }
}
