import CoreGraphics
import AppKit
import ApplicationServices

final class KeybindingService {
    static let shared = KeybindingService()

    private struct Binding {
        let label: String
        let modifiers: NSEvent.ModifierFlags
        let key: String?
        let keyCode: UInt16?
        let action: () -> Void
    }

    private var bindings: [Binding] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var heldModifiers: NSEvent.ModifierFlags = []

    private init() {}

    func start() {
        guard AXIsProcessTrusted() else {
            print("KeybindingService: Accessibility trust not granted — global shortcuts inactive")
            return
        }
        let candidates = makeCandidates()
        guard buildBindings(from: candidates) else { return }
        installEventTap()
    }

    private func makeCandidates() -> [(String, String, () -> Void)] {
        let config = MenuConfig.shared
        return [
            (config.openShortcut, "open", {
                DispatchQueue.main.async {
                    if NSApp.keyWindow != nil {
                        NotificationCenter.default.post(name: .menuCycleSelection, object: nil)
                    } else {
                        NotificationCenter.default.post(name: .menuShowPanel, object: nil,
                            userInfo: ["windows": false, "all": false])
                    }
                }
            }),
            (config.openWindowsShortcut, "openWindows", {
                DispatchQueue.main.async {
                    if NSApp.keyWindow != nil {
                        NotificationCenter.default.post(name: .menuCycleSelection, object: nil)
                    } else {
                        NotificationCenter.default.post(name: .menuShowPanel, object: nil,
                            userInfo: ["windows": true, "all": true, "noSearch": true])
                    }
                }
            }),
        ]
    }

    private func buildBindings(from candidates: [(String, String, () -> Void)]) -> Bool {
        let allShortcuts = candidates.compactMap { s, _, _ in s.isEmpty ? nil : s }
        if let duplicate = findDuplicate(allShortcuts) {
            print("KeybindingService: duplicate shortcut '\(duplicate)' — all shortcuts disabled")
            bindings = []
            return false
        }

        bindings = []
        for (shortcut, label, action) in candidates {
            guard !shortcut.isEmpty, let parsed = parse(shortcut) else { continue }
            bindings.append(Binding(label: label, modifiers: parsed.modifiers, key: parsed.key, keyCode: parsed.keyCode, action: action))
        }

        guard !bindings.isEmpty else {
            print("KeybindingService: no shortcuts configured")
            return false
        }
        return true
    }

    private func installEventTap() {
        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon, let tap = Unmanaged<KeybindingService>.fromOpaque(refcon).takeUnretainedValue().eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }
                guard let refcon else {
                    return Unmanaged.passRetained(event)
                }
                let service = Unmanaged<KeybindingService>.fromOpaque(refcon).takeUnretainedValue()

                if type == .flagsChanged, !service.heldModifiers.isEmpty {
                    guard let nsEvent = NSEvent(cgEvent: event) else {
                        return Unmanaged.passRetained(event)
                    }
                    let flags = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
                    if flags.intersection(service.heldModifiers).isEmpty {
                        service.heldModifiers = []
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .menuRunSelected, object: nil)
                        }
                    }
                    return Unmanaged.passRetained(event)
                }

                guard type == .keyDown else {
                    return Unmanaged.passRetained(event)
                }
                guard let nsEvent = NSEvent(cgEvent: event) else {
                    return Unmanaged.passRetained(event)
                }
                let flags = nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
                for binding in service.bindings {
                    guard flags == binding.modifiers else { continue }
                    if let keyCode = binding.keyCode {
                        guard nsEvent.keyCode == keyCode else { continue }
                    } else if let key = binding.key {
                        guard nsEvent.charactersIgnoringModifiers == key else { continue }
                    } else { continue }
                    if binding.keyCode == 48 {
                        service.heldModifiers = binding.modifiers
                    }
                    let action = binding.action
                    action()
                    return nil
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: userInfo
        ) else {
            print("KeybindingService: failed to create event tap")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        print("KeybindingService: registered \(bindings.count) shortcut(s)")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        bindings = []
    }

    func restart() {
        stop()
        start()
    }

    func clearHeldModifiers() {
        heldModifiers = []
    }

    // MARK: - Parsing

    private struct ParsedBinding {
        let modifiers: NSEvent.ModifierFlags
        let key: String?
        let keyCode: UInt16?
    }

    private func findDuplicate(_ shortcuts: [String]) -> String? {
        var seen: Set<String> = []
        for shortcut in shortcuts {
            let normalized = normalize(shortcut)
            if !seen.insert(normalized).inserted { return shortcut }
        }
        return nil
    }

    private func normalize(_ shortcut: String) -> String {
        let tokens = shortcut.lowercased().split(separator: "+").map(String.init)
        guard tokens.count >= 2 else { return shortcut.lowercased() }
        let key = tokens.last!
        let mods = tokens.dropLast().map { token -> String in
            switch token {
            case "command":            return "cmd"
            case "control":            return "ctrl"
            case "alt", "option":      return "opt"
            case "enter":              return "return"
            default:                   return token
            }
        }.sorted()
        let normalizedKey = key == "enter" ? "return" : key
        return (mods + [normalizedKey]).joined(separator: "+")
    }

    private func parse(_ shortcut: String) -> ParsedBinding? {
        let tokens = shortcut.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard tokens.count >= 2 else { return nil }
        let rawKey = tokens.last!
        guard !rawKey.isEmpty else { return nil }
        var modifiers: NSEvent.ModifierFlags = []
        for token in tokens.dropLast() {
            switch token {
            case "cmd", "command": modifiers.insert(.command)
            case "shift":          modifiers.insert(.shift)
            case "ctrl", "control": modifiers.insert(.control)
            case "alt", "opt", "option": modifiers.insert(.option)
            default:
                print("KeybindingService: unknown modifier '\(token)' in shortcut '\(shortcut)'")
                return nil
            }
        }
        switch rawKey {
        case "left":           return ParsedBinding(modifiers: modifiers, key: nil, keyCode: 123)
        case "right":          return ParsedBinding(modifiers: modifiers, key: nil, keyCode: 124)
        case "down":           return ParsedBinding(modifiers: modifiers, key: nil, keyCode: 125)
        case "up":             return ParsedBinding(modifiers: modifiers, key: nil, keyCode: 126)
        case "enter", "return": return ParsedBinding(modifiers: modifiers, key: nil, keyCode: 36)
        case "space":          return ParsedBinding(modifiers: modifiers, key: nil, keyCode: 49)
        case "tab":            return ParsedBinding(modifiers: modifiers, key: nil, keyCode: 48)
        default:               return ParsedBinding(modifiers: modifiers, key: rawKey, keyCode: nil)
        }
    }
}

extension Notification.Name {
    static let menuShowPanel = Notification.Name("menuShowPanel")
    static let menuCycleSelection = Notification.Name("menuCycleSelection")
    static let menuRunSelected = Notification.Name("menuRunSelected")
}
