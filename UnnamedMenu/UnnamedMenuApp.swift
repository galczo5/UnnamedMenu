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

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown && event.keyCode == 48 {
            NotificationCenter.default.post(name: .tabKeyPressed, object: nil)
            return
        }
        super.sendEvent(event)
    }
}

extension Notification.Name {
    static let tabKeyPressed = Notification.Name("tabKeyPressed")
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
    private let showAllFlag = CommandLine.arguments.contains("--all")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // CLI-only generators — print JSON and exit, no UI or instance logic needed.
        if CommandLine.arguments.contains("--applications") {
            ApplicationsGenerator().generateForCLI()
        }
        let windowsFlag = CommandLine.arguments.contains("--windows")
        let openFlag = CommandLine.arguments.contains("--open")
        if windowsFlag && !openFlag {
            if let cached = WindowCache.read() {
                print(cached)
                exit(0)
            }
            WindowsGenerator().generateForCLI()
        }

        // Use an exclusive non-blocking file lock to determine the main instance.
        // flock() is atomic — no race window between concurrent launches.
        // The lock is held until the process exits (fd stays open for app lifetime).
        let lockPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("com.unnamedmenu.instance.lock")
        let lockFd = Darwin.open(lockPath, O_CREAT | O_RDWR, mode_t(0o644))
        var lock = Darwin.flock()
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)
        lock.l_start = 0
        lock.l_len = 0
        let isMainInstance = lockFd >= 0 && fcntl(lockFd, F_SETLK, &lock) != -1

        // --windows --open: inject windows JSON as piped input (prefer cache written by main instance).
        var pipedData: Data?
        if windowsFlag && openFlag {
            let tOpen0 = Date()
            if let cached = WindowCache.read() {
                pipedData = cached.data(using: .utf8)
                print("[--windows --open] cache hit: \(Int(Date().timeIntervalSince(tOpen0) * 1000))ms")
            } else {
                print("[--windows --open] cache miss, running live enumeration")
                let items = WindowsGenerator().generateItems()
                pipedData = try? JSONSerialization.data(withJSONObject: items)
                print("[--windows --open] live enumeration: \(Int(Date().timeIntervalSince(tOpen0) * 1000))ms")
            }
        } else if isatty(STDIN_FILENO) == 0 {
            // Read piped input (blocks until the upstream process closes the pipe).
            let data = FileHandle.standardInput.readDataToEndOfFile()
            if !data.isEmpty { pipedData = data }
        }

        if !isMainInstance {
            // Another instance owns the lock — delegate and exit.
            if let data = pipedData,
               let items = try? JSONDecoder().decode([CommandItem].self, from: data), !items.isEmpty,
               let json = String(data: data, encoding: .utf8) {
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name(AppDelegate.pipeConfigNotification),
                    object: nil,
                    userInfo: ["json": json, "all": showAllFlag ? "1" : "0"],
                    deliverImmediately: true
                )
            } else if let idx = CommandLine.arguments.firstIndex(of: "--config"),
                      CommandLine.arguments.indices.contains(idx + 1) {
                let url = URL(fileURLWithPath: CommandLine.arguments[idx + 1]).standardizedFileURL
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name(AppDelegate.filterConfigNotification),
                    object: nil,
                    userInfo: ["path": url.path, "all": showAllFlag ? "1" : "0"],
                    deliverImmediately: true
                )
            } else if CommandLine.arguments.contains("--open") {
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name(AppDelegate.showPanelNotification),
                    object: nil,
                    userInfo: ["all": showAllFlag ? "1" : "0"],
                    deliverImmediately: true
                )
            }
            exit(0)
        }

        // We are the main instance — set up UI.
        if let data = pipedData,
           let items = try? JSONDecoder().decode([CommandItem].self, from: data), !items.isEmpty {
            pendingPipedItems = items
        }
        if let idx = CommandLine.arguments.firstIndex(of: "--config"),
           CommandLine.arguments.indices.contains(idx + 1) {
            pendingConfigURL = URL(fileURLWithPath: CommandLine.arguments[idx + 1]).standardizedFileURL
        }

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

        DispatchQueue.global(qos: .utility).async { WindowCache.rebuild(trigger: "launch") }
        let wsNC = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            wsNC.addObserver(forName: name, object: nil, queue: .main) { _ in
                let trigger = name.rawValue.components(separatedBy: ".").last ?? name.rawValue
                DispatchQueue.global(qos: .utility).async { WindowCache.rebuild(trigger: trigger) }
            }
        }

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

        appState.showAll = showAllFlag
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
        appState.showAll = note.userInfo?["all"] as? String == "1"
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
