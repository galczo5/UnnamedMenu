import AppKit

final class DimOverlay {
    static let shared = DimOverlay()
    private var window: NSWindow?
    private init() {}

    func show(screen: NSScreen) {
        guard MenuConfig.shared.dimEnabled else { return }

        let win = window ?? makeWindow()
        window = win

        win.setFrame(screen.frame, display: false)
        win.alphaValue = 0
        win.order(.below, relativeTo: NSApp.keyWindow?.windowNumber ?? 0)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().alphaValue = MenuConfig.shared.dimOpacity
        }
    }

    func hide() {
        guard let win = window, win.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            win.animator().alphaValue = 0
        }, completionHandler: {
            win.orderOut(nil)
        })
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .black
        win.ignoresMouseEvents = true
        win.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        win.collectionBehavior = [.canJoinAllSpaces, .transient]
        win.isReleasedWhenClosed = false
        return win
    }
}
