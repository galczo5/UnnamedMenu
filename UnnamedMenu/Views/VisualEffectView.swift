import SwiftUI
import AppKit

struct VisualEffectView: NSViewRepresentable {
    var theme: String = "light"

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        switch theme {
        case "dark":
            nsView.appearance = NSAppearance(named: .darkAqua)
            nsView.material = .popover
            nsView.blendingMode = .withinWindow
        case "system":
            nsView.appearance = nil
            nsView.material = .underWindowBackground
            nsView.blendingMode = .behindWindow
        default:
            nsView.appearance = NSAppearance(named: .aqua)
            nsView.material = .underWindowBackground
            nsView.blendingMode = .behindWindow
        }
    }
}
