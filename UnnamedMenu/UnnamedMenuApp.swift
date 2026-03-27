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

    private static let showPanelNotification    = "com.unnamedmenu.showPanel"
    private static let filterConfigNotification = "com.unnamedmenu.filterConfig"
    private static let pipeConfigNotification   = "com.unnamedmenu.pipeConfig"
    private var pendingConfigURL: URL?
    private var pendingPipedItems: [CommandItem]?
    private let showAllFlag     = CommandLine.arguments.contains("--all")
    private let momentaryFlag   = CommandLine.arguments.contains("--momentary")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isatty(STDIN_FILENO) == 0 {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            if let items = try? JSONDecoder().decode([CommandItem].self, from: data), !items.isEmpty {
                let myPID = ProcessInfo.processInfo.processIdentifier
                let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                    .filter { $0.processIdentifier != myPID }
                if others.first != nil {
                    if let json = String(data: data, encoding: .utf8) {
                        DistributedNotificationCenter.default().postNotificationName(
                            NSNotification.Name(AppDelegate.pipeConfigNotification),
                            object: nil,
                            userInfo: ["json": json, "all": showAllFlag ? "1" : "0"],
                            deliverImmediately: true
                        )
                    }
                    exit(0)
                }
                pendingPipedItems = items
            }
        }

        if CommandLine.arguments.contains("--applications") {
            ApplicationsGenerator().generateForCLI()
        }

        if CommandLine.arguments.contains("--windows") {
            WindowsGenerator().generateForCLI()
        }

        if let idx = CommandLine.arguments.firstIndex(of: "--config"),
           CommandLine.arguments.indices.contains(idx + 1) {
            let url = URL(fileURLWithPath: CommandLine.arguments[idx + 1]).standardizedFileURL
            let myPID = ProcessInfo.processInfo.processIdentifier
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .filter { $0.processIdentifier != myPID }
            if others.first != nil {
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name(AppDelegate.filterConfigNotification),
                    object: nil,
                    userInfo: ["path": url.path, "all": showAllFlag ? "1" : "0"],
                    deliverImmediately: true
                )
                exit(0)
            }
            pendingConfigURL = url
        }

        if CommandLine.arguments.contains("--open") {
            let myPID = ProcessInfo.processInfo.processIdentifier
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .filter { $0.processIdentifier != myPID }
            if others.first != nil {
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name(AppDelegate.showPanelNotification),
                    object: nil,
                    userInfo: ["all": showAllFlag ? "1" : "0", "momentary": momentaryFlag ? "1" : "0"],
                    deliverImmediately: true
                )
                exit(0)
            }
            // No existing instance — fall through to normal launch
        }

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
        showPanel()

        appState.momentaryMode = momentaryFlag
        appState.showAll = showAllFlag || momentaryFlag
        if let url = pendingConfigURL {
            appState.applyFilter(url: url)
        }
        if let items = pendingPipedItems {
            appState.applyItems(items)
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showPanelFromNotification),
            name: NSNotification.Name(AppDelegate.showPanelNotification),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(filterConfigFromNotification(_:)),
            name: NSNotification.Name(AppDelegate.filterConfigNotification),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(pipeConfigFromNotification(_:)),
            name: NSNotification.Name(AppDelegate.pipeConfigNotification),
            object: nil
        )
    }

    @objc private func pipeConfigFromNotification(_ note: Notification) {
        guard let json = note.userInfo?["json"] as? String,
              let data = json.data(using: .utf8),
              let items = try? JSONDecoder().decode([CommandItem].self, from: data) else { return }
        appState.showAll = note.userInfo?["all"] as? String == "1"
        appState.applyItems(items)
        showPanel()
    }

    @objc private func filterConfigFromNotification(_ note: Notification) {
        guard let path = note.userInfo?["path"] as? String else { return }
        appState.showAll = note.userInfo?["all"] as? String == "1"
        appState.applyFilter(url: URL(fileURLWithPath: path))
        showPanel()
    }

    @objc private func showPanelFromNotification(_ note: Notification) {
        let momentary = note.userInfo?["momentary"] as? String == "1"
        appState.momentaryMode = momentary
        appState.showAll = note.userInfo?["all"] as? String == "1" || momentary
        showPanel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showPanel()
        return false
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let open = NSMenuItem(title: "Open", action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        let generate = NSMenuItem(title: "Generate applications.json", action: #selector(generateApplicationsJSON), keyEquivalent: "")
        generate.target = self
        menu.addItem(generate)
        menu.addItem(.separator())

        let reload = NSMenuItem(title: "Reload Configuration", action: #selector(reloadConfig), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
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

    private func showPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.visibleFrame
        let pf = panel.frame
        panel.setFrameOrigin(NSPoint(x: sf.midX - pf.width / 2, y: sf.maxY - sf.height * 0.33 - pf.height))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openPanel() {
        showPanel()
    }

    @objc private func reloadConfig() {
        appState.reload()
        rebuildMenu()
    }

    @objc private func generateApplicationsJSON() {
        guard ApplicationsGenerator().generate() else { return }
        appState.reload()
        rebuildMenu()
    }
}
