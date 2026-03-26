//
//  UnnamedMenuApp.swift
//  UnnamedMenu
//
//  Created by Kamil on 26/03/2026.
//

import SwiftUI
import AppKit

@main
struct UnnamedMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            // Disable New Window (Cmd+N) — this is a single-window launcher
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }
            window.styleMask = [.borderless]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.level = .floating
            window.hasShadow = true
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return false
    }
}
