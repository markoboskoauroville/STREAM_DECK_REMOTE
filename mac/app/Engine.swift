import AppKit

/// One deck, two faces (Marko, 6.11.2026: "this application controls both Stream Deck and Stream Deck APK. And if
/// something is clicked on the Stream Deck APK, I can see it on original Stream Deck and vice versa ... everything is
/// connected in one network"). The Engine holds the one profile in use and its 15 keys; the real Elgato deck (USB)
/// and the phone (HTTP) both show it and both press it. A press, from either, enlarges the key on both for a moment
/// ("when I press button, the button enlarges for certain percentage and then come back"), then the key acts.
final class Engine {
    static let profiles = ["apps", "obs"]
    static let flashSeconds = 0.16
    static let flashScale: CGFloat = 1.18

    let apps: Apps
    let obs: OBS
    let deck = Deck()
    var onChange: () -> Void = {}
    private(set) var deckStatus = "Looking for the Stream Deck…"
    private(set) var profile = UserDefaults.standard.string(forKey: "profile") ?? "apps"
    /// The key enlarged right now (-1: none); the last pressed key and the press count, for the phone.
    private(set) var flashKey = -1
    private(set) var lastPressed = -1
    private(set) var presses = 0

    init(apps: Apps, obs: OBS) { self.apps = apps; self.obs = obs }

    func start() {
        apps.onChange = { [weak self] in self?.changed() }
        obs.onChange = { [weak self] in self?.changed() }
        deck.onPress = { [weak self] k in self?.press(k) }
        deck.onChange = { [weak self] s in
            DispatchQueue.main.async { self?.deckStatus = s; self?.render(force: true); self?.onChange() }
        }
        // only one program can hold the deck: Stream Deck Control (Mantra), which this app follows, lets it go
        for a in NSRunningApplication.runningApplications(withBundleIdentifier: "community.auroville.streamdeckcontrol") { a.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.deck.start() }
        render(force: true)
    }

    func stop() { deck.clear() }

    func keys() -> [[String: Any]] {
        var k = profile == "obs" ? obs.keys() : apps.keys()
        while k.count < Deck.keys { k.append(["kind": "empty"]) }
        return Array(k.prefix(Deck.keys))
    }

    var title: String { profile == "obs" ? obs.title : apps.title }
    var note: String { profile == "obs" ? obs.note : apps.note }

    func changed() { render(); onChange() }

    func setProfile(_ p: String) {
        guard p != profile, Engine.profiles.contains(p) else { return }
        profile = p
        UserDefaults.standard.set(p, forKey: "profile")
        render(force: true)
        onChange()
    }

    /// A key pressed on the real deck or on the phone: enlarged on both, then it acts and comes back.
    func press(_ i: Int) {
        guard (0..<Deck.keys).contains(i), keys()[i]["kind"] as? String != "empty" else { return }
        presses += 1
        lastPressed = i
        flashKey = i
        let n = presses
        render()
        onChange()
        let p = profile
        DispatchQueue.main.asyncAfter(deadline: .now() + Engine.flashSeconds) { [weak self] in
            guard let self = self else { return }
            if self.presses == n { self.flashKey = -1 }
            if p == "obs" { self.obs.press(i) } else { self.apps.press(i) }
            self.render()
            self.onChange()
        }
    }

    /// The real deck's 15 pictures; a key whose picture did not change is not sent again.
    func render(force: Bool = false) {
        guard deck.connected else { return }
        if force { deck.forget() }
        for (i, k) in keys().enumerated() {
            let (img, hash) = KeyArt.draw(k, scale: i == flashKey ? Engine.flashScale : 1)
            deck.show(i, img, hash: hash)
        }
    }
}

/// The picture on one key of the real deck, 72 × 72, the same as the phone draws it: an app's icon with its name and
/// the green bar when in front; a scene's big number, green and ringed when live; NEXT; F1 / F2 filling the key.
enum KeyArt {
    static let green = NSColor(red: 0x33 / 255.0, green: 0xD1 / 255.0, blue: 0x7A / 255.0, alpha: 1)

    static func draw(_ k: [String: Any], scale: CGFloat = 1, size: Int = Deck.px) -> (NSBitmapImageRep, Int) {
        let kind = k["kind"] as? String ?? "empty", label = k["label"] as? String ?? ""
        let icon = k["icon"] as? String ?? "", active = k["active"] as? Bool ?? false
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let s = CGFloat(size), u = s / 72
        NSColor.black.setFill(); NSRect(x: 0, y: 0, width: s, height: s).fill()
        if scale != 1 {
            let t = NSAffineTransform()
            t.translateX(by: s / 2, yBy: s / 2); t.scale(by: scale); t.translateX(by: -s / 2, yBy: -s / 2)
            t.concat()
        }
        func text(_ t: String, _ pt: CGFloat, _ y: CGFloat, _ c: NSColor, _ w: NSFont.Weight = .semibold) {
            let p = NSMutableParagraphStyle(); p.alignment = .center; p.lineBreakMode = .byTruncatingTail
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: pt * u, weight: w),
                                                    .foregroundColor: c, .paragraphStyle: p]
            (t as NSString).draw(in: NSRect(x: 2 * u, y: y * u, width: s - 4 * u, height: pt * 1.4 * u), withAttributes: a)
        }
        func big(_ t: String, _ pt: CGFloat, _ c: NSColor) {
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: pt * u, weight: .heavy), .foregroundColor: c]
            let sz = (t as NSString).size(withAttributes: a)
            (t as NSString).draw(at: NSPoint(x: (s - sz.width) / 2, y: (s - sz.height) / 2), withAttributes: a)
        }
        switch kind {
        case "app", "open":
            Apps.image(icon)?.draw(in: NSRect(x: 10 * u, y: 18 * u, width: 52 * u, height: 52 * u))
            text(label, 10, 3, .white)
            if active { green.setFill(); NSRect(x: 10 * u, y: 15 * u, width: 52 * u, height: 3 * u).fill() }
        case "scene":
            if active {
                green.setStroke()
                let r = NSBezierPath(roundedRect: NSRect(x: 2 * u, y: 2 * u, width: s - 4 * u, height: s - 4 * u), xRadius: 8 * u, yRadius: 8 * u)
                r.lineWidth = 3 * u; r.stroke()
            }
            big(label, label.count > 2 ? 26 : 36, active ? green : .white)
        case "next":
            text("NEXT", 17, 36, .white, .bold)
            text("▶", 16, 20, green)
            text(label, 11, 5, NSColor(white: 0.6, alpha: 1))
        case "fkey":
            big(label, 40, .white)
        default: break
        }
        NSGraphicsContext.restoreGraphicsState()
        return (rep, "\(kind)|\(label)|\(icon)|\(active)|\(scale)".hashValue)
    }
}
