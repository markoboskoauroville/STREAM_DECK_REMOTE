import AppKit

/// APPS, the application switcher on the phone: the same rules as Stream Deck Control (Mantra) on the real deck
/// (Marko, 31.10.2026): every app with a Dock icon, in the order it was opened (Finder first), a pressed app moves to
/// the first key, the app in front has a green bar. Up to 15 on a page; with more, 14 per page and key 15 is NEXT.
final class Apps {
    var onChange: () -> Void = {}
    private var order: [pid_t] = []
    private var page = 0
    private var watching: [NSObjectProtocol] = []

    static var saved: [String] {
        get { UserDefaults.standard.stringArray(forKey: "pressedOrder") ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(60)), forKey: "pressedOrder") }
    }

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                  NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                  NSWorkspace.didUnhideApplicationNotification] {
            watching.append(nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.onChange() })
        }
    }

    private func apps() -> [NSRunningApplication] {
        let me = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated }
            .sorted { a, b in
                let ia = Apps.saved.firstIndex(of: a.bundleIdentifier ?? "") ?? Int.max
                let ib = Apps.saved.firstIndex(of: b.bundleIdentifier ?? "") ?? Int.max
                if ia != ib { return ia < ib }
                if (a.bundleIdentifier == "com.apple.finder") != (b.bundleIdentifier == "com.apple.finder") {
                    return a.bundleIdentifier == "com.apple.finder"
                }
                return (a.launchDate ?? .distantPast, a.processIdentifier) < (b.launchDate ?? .distantPast, b.processIdentifier)
            }
        let pids = Set(running.map(\.processIdentifier))
        order = order.filter { pids.contains($0) }
        for a in running where !order.contains(a.processIdentifier) { order.append(a.processIdentifier) }
        return order.compactMap { pid in running.first { $0.processIdentifier == pid } }
    }

    /// The 15 keys, as on Stream Deck Control (Mantra) v3 (Marko, 1.11.2026: "The last button is F2. The one before
    /// last is F1. The third button from the back is Next Page."): apps on keys 1-12, NEXT 13, F1 14, F2 15.
    private func layout() -> [([String: Any], NSRunningApplication?)] {
        let all = apps()
        let per = 12
        let pages = max(1, (all.count + per - 1) / per)
        page = min(page, pages - 1)
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var k: [([String: Any], NSRunningApplication?)] = all.dropFirst(page * per).prefix(per).map { a in
            (["kind": "app", "label": Apps.name(a), "icon": Apps.iconId(a), "active": a.processIdentifier == front], a)
        }
        while k.count < per { k.append((["kind": "empty"], nil)) }
        k.append((["kind": "next", "label": "\(page + 1) / \(pages)"], nil))
        k.append((["kind": "fkey", "label": "F1"], nil))
        k.append((["kind": "fkey", "label": "F2"], nil))
        return k
    }

    func keys() -> [[String: Any]] { layout().map { $0.0 } }

    var title: String { NSWorkspace.shared.frontmostApplication.map { Apps.name($0) } ?? "" }
    var note: String { "APPLICATION SWITCHER · \(order.count) apps open" }

    func press(_ i: Int) {
        let k = layout()
        guard i >= 0, i < k.count else { return }
        switch k[i].0["kind"] as? String {
        case "next":
            page += 1
            if page * 12 >= order.count { page = 0 }
            onChange()
        case "fkey":
            FunctionKey.press(i == 13 ? 1 : 2)
        case "app":
            guard let a = k[i].1 else { return }
            order.removeAll { $0 == a.processIdentifier }
            order.insert(a.processIdentifier, at: 0)
            if let id = a.bundleIdentifier { Apps.saved = [id] + Apps.saved.filter { $0 != id } }
            page = 0
            Apps.bringFront(a)
            onChange()
        default: break
        }
    }

    static func name(_ a: NSRunningApplication) -> String {
        (a.localizedName ?? a.bundleURL?.deletingPathExtension().lastPathComponent ?? "?")
            .replacingOccurrences(of: " (Mantra)", with: "")
    }

    static func iconId(_ a: NSRunningApplication) -> String { a.bundleIdentifier ?? "pid:\(a.processIdentifier)" }

    /// Front with every window, as a Dock click does (Stream Deck Control's own way).
    static func bringFront(_ a: NSRunningApplication) {
        a.unhide()
        if let url = a.bundleURL {
            let c = NSWorkspace.OpenConfiguration(); c.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: c) { _, _ in }
        } else {
            a.activate(options: [.activateAllWindows])
        }
    }

    // MARK: icons, PNG 160 px, by bundle id (or pid:<n>)
    private static var cache: [String: Data] = [:]

    static func image(_ id: String) -> NSImage? {
        if id.hasPrefix("pid:"), let pid = Int32(id.dropFirst(4)) { return NSRunningApplication(processIdentifier: pid)?.icon }
        if let a = NSRunningApplication.runningApplications(withBundleIdentifier: id).first { return a.icon }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return NSWorkspace.shared.icon(forFile: url.path) }
        return nil
    }

    static func icon(_ id: String) -> Data? {
        if let d = cache[id] { return d }
        var img: NSImage?
        if id.hasPrefix("pid:"), let pid = Int32(id.dropFirst(4)) {
            img = NSRunningApplication(processIdentifier: pid)?.icon
        } else if let a = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            img = a.icon
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            img = NSWorkspace.shared.icon(forFile: url.path)
        }
        guard let i = img else { return nil }
        let px = 160
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        i.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let d = rep.representation(using: .png, properties: [:])
        if let d = d, !id.hasPrefix("pid:") { cache[id] = d }
        return d
    }
}
