import SwiftUI
import AppKit

@main
struct UnnamedMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { }
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Close any default windows SwiftUI may have created
        for window in NSApp.windows { window.close() }

        // Status bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "UnnamedMenu")
            image?.isTemplate = true
            button.image = image
        }

        appState.reload()
        rebuildMenu()

        // Launcher panel
        let hostingView = NSHostingView(rootView: ContentView().environmentObject(appState))
        hostingView.setFrameSize(hostingView.fittingSize)

        panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .floating
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.center()
        panel.orderFrontRegardless()
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.panel.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return false
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let reload = NSMenuItem(title: "Reload Configuration", action: #selector(reloadConfig), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)
        menu.addItem(.separator())

        if appState.loadedFileNames.isEmpty {
            let none = NSMenuItem(title: "No config files loaded", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for name in appState.loadedFileNames {
                let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        statusItem.menu = menu
    }

    @objc private func reloadConfig() {
        appState.reload()
        rebuildMenu()
    }
}
