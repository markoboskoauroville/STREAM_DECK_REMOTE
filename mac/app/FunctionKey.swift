import AppKit

/// F1 and F2 from Stream Deck Control (Mantra) v3, unchanged: keys 14 and 15 of APPS.
enum FunctionKey {
    static let codes = [1: CGKeyCode(122), 2: CGKeyCode(120)]      // kVK_F1, kVK_F2

    /// Asked fresh each time: AXIsProcessTrusted sees a change made in Settings at once, while CGPreflightPostEventAccess
    /// keeps its first answer until the app restarts (Marko, 1.11.2026: it "didn't detect that I changed it until I restarted").
    static var allowed: Bool { AXIsProcessTrusted() }

    static func press(_ n: Int) {
        guard let code = codes[n] else { return }
        guard allowed else { askPermission(); return }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = .maskSecondaryFn                               // a real F key carries the fn flag
            e?.post(tap: .cghidEventTap)
        }
    }

    static func askPermission() {
        _ = CGRequestPostEventAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
