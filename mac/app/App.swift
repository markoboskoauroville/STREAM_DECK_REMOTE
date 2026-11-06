// Stream Deck Remote (Mantra): the Mac's half of Stream Deck Remote on the phone (Marko, 6.11.2026: "this is Android
// application, which looks like a stream deck ... and can be controlled by helper application you're going to build
// ... If we can avoid ADB even better ... if they're on the same Wi-Fi network. That should work."). It serves the
// phone's profiles, APPS (the application switcher) and OBS (one numbered key per scene), on port 8963.
import AppKit
import SwiftUI

let VERSION = 10
let NAME = "Stream Deck Remote (Mantra)"

final class Model: ObservableObject {
    @Published var lastPhone = "no phone yet"
    @Published var lastSeen: Date?
    @Published var cable: [String] = []
    @Published var obsLine = ""
    @Published var serverLine = ""
    @Published var addresses: [String] = []
    @Published var deckLine = ""
    @Published var profile = ""
    @Published var keysAllowed = true
    @Published var cableOn = true
    @Published var keyImages: [NSImage] = []
    @Published var title = ""
    @Published var note = ""

    let apps = Apps()
    let obs = OBS()
    let cableLink = Cable()
    lazy var engine = Engine(apps: apps, obs: obs)
    lazy var server = Server(engine: engine)

    func start() {
        engine.onChange = { [weak self] in self?.server.changed(); self?.refresh() }
        cableLink.onChange = { [weak self] in self?.refresh() }
        server.onSeen = { [weak self] who in
            guard let self = self else { return }
            self.lastPhone = who; self.lastSeen = Date()
        }
        apps.start()
        obs.start()
        engine.start()
        server.start()
        cableLink.start()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func refresh() {
        obsLine = obs.summary
        serverLine = server.status
        cable = cableLink.phones
        addresses = Model.ipv4()
        deckLine = engine.deckStatus
        profile = engine.profile
        keysAllowed = FunctionKey.allowed
        cableOn = cableLink.enabled
        // the deck as the phone and the real deck show it (v10), drawn larger for the window; the pressed key enlarged
        keyImages = engine.keys().enumerated().map { i, k in
            let (rep, _) = KeyArt.draw(k, scale: i == engine.flashKey ? Engine.flashScale : 1, size: 144)
            let img = NSImage(size: NSSize(width: 72, height: 72)); img.addRepresentation(rep); return img
        }
        title = engine.title
        note = engine.note
    }

    /// This Mac's addresses a phone can type (Wi-Fi, cable, Tailscale), without the loopback.
    static func ipv4() -> [String] {
        var out: [String] = []
        var ifa: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifa) == 0, let first = ifa else { return out }
        defer { freeifaddrs(ifa) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let sa = p.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: p.pointee.ifa_name)
            guard name != "lo0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                if !ip.hasPrefix("169.254.") && !ip.hasPrefix("198.18.") { out.append("\(ip)  (\(name))") }
            }
        }
        return out
    }
}

struct Panel: View {
    @ObservedObject var m: Model
    let close: () -> Void

    private let green = Color(red: 0x33 / 255.0, green: 0xD1 / 255.0, blue: 0x7A / 255.0)
    private let grey = Color(white: 0.55)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button { } label: { Text("ON").font(.system(size: 13, weight: .bold)).foregroundColor(green) }
                    .buttonStyle(.plain).focusable(false).accessibilityIdentifier("on")
                Button { m.engine.stop(); m.server.stop(); NSApp.terminate(nil) } label: {
                    Text("OFF").font(.system(size: 13, weight: .bold)).foregroundColor(grey)
                }.buttonStyle(.plain).focusable(false).accessibilityIdentifier("off")
                Text(NAME).font(.system(size: 13, weight: .semibold))
                Spacer()
                if !m.keysAllowed {
                    // F1 / F2 post keys, which needs Accessibility (MANTRA_MANIFEST: amber PERMISSIONS top right)
                    Button { FunctionKey.askPermission() } label: {
                        Text("PERMISSIONS").font(.system(size: 11, weight: .bold)).foregroundColor(.orange)
                    }.buttonStyle(.plain).accessibilityIdentifier("permissions")
                }
                Button(action: close) {
                    Image(systemName: "xmark").foregroundColor(grey).frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).focusable(false).accessibilityIdentifier("close")
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    deck
                    details
                }
                .padding(16)
            }
        }
        .frame(minWidth: 440, minHeight: 420)
        .background(Color(red: 0x0B / 255.0, green: 0x0B / 255.0, blue: 0x0C / 255.0))
    }

    /// The same view as the phone (Marko, 6.11.2026: "if I open stream remote, I want to have the same view as on my
    /// phone, plus all other technical details below it. So I can also switch the profiles on the computer and it will
    /// be switched on my stream deck"): the 15 keys (a click presses), the live line, the profile tabs.
    private var deck: some View {
        VStack(spacing: 10) {
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { r in
                    HStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { c in
                            let i = r * 5 + c
                            Button { m.engine.press(i) } label: {
                                Group {
                                    if i < m.keyImages.count { Image(nsImage: m.keyImages[i]).resizable().interpolation(.high) }
                                    else { Color.black }
                                }
                                .frame(width: 66, height: 66)
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color(white: 0.16), lineWidth: 1))
                            }
                            .buttonStyle(.plain).focusable(false).accessibilityIdentifier("key\(i + 1)")
                        }
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.11)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(white: 0.17), lineWidth: 1))
            Text(m.title).font(.system(size: 15, weight: .semibold)).foregroundColor(.white).lineLimit(1)
            Text(m.note).font(.system(size: 12)).foregroundColor(grey).lineLimit(2).multilineTextAlignment(.center)
            HStack(spacing: 8) {
                ForEach(Engine.profiles, id: \.self) { p in
                    let sel = p == m.profile
                    Button { m.engine.setProfile(p) } label: {
                        VStack(spacing: 5) {
                            Text(p.uppercased()).font(.system(size: 13, weight: sel ? .bold : .medium)).tracking(1.5)
                                .foregroundColor(sel ? .white : grey)
                            RoundedRectangle(cornerRadius: 2).fill(sel ? green : Color.clear).frame(width: 26, height: 3)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(sel ? Color(white: 0.11) : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).focusable(false).accessibilityIdentifier("profile-\(p)")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            section("THE STREAM DECK") {
                line(m.deckLine)
                line("The real deck and the phone show the same keys; a press on either shows on both.")
            }
            section("THE PHONE") {
                line("Stream Deck Remote on the phone finds this Mac by itself on the same Wi-Fi, or over the cable.")
                line("Last asked by: \(m.lastPhone)" + (m.lastSeen.map { " · \(Int(-$0.timeIntervalSinceNow)) s ago" } ?? ""))
                line("Server: \(m.serverLine)")
            }
            section("THIS MAC'S ADDRESSES (port \(PORT))") {
                ForEach(m.addresses, id: \.self) { a in line(a).textSelection(.enabled) }
            }
            section("CABLE / ADB (not needed on Wi-Fi)") {
                HStack(spacing: 12) {
                    Button { m.cableLink.enabled = true; m.refresh() } label: {
                        Text("ON").font(.system(size: 12, weight: .bold)).foregroundColor(m.cableOn ? green : grey)
                    }.buttonStyle(.plain).accessibilityIdentifier("cableOn")
                    Button { m.cableLink.enabled = false; m.refresh() } label: {
                        Text("OFF").font(.system(size: 12, weight: .bold)).foregroundColor(m.cableOn ? grey : green)
                    }.buttonStyle(.plain).accessibilityIdentifier("cableOff")
                }
                line(!m.cableOn ? "off: the phone uses the Wi-Fi only"
                     : m.cable.isEmpty ? "no phone on adb" : m.cable.joined(separator: ", ") + " · adb reverse on")
            }
            section("PROFILES") {
                line("APPS · application switcher, apps on 1–12, NEXT, F1, F2")
                line("OBS · \(m.obsLine)")
                line("The real deck cannot switch profiles; the tabs above (or on the phone) switch all three.")
            }
            Text("v\(VERSION)").font(.system(size: 11)).foregroundColor(grey)
        }
    }

    @ViewBuilder private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .bold)).foregroundColor(grey)
            c()
        }
    }

    private func line(_ t: String) -> some View {
        Text(t).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()
    var window: NSWindow!

    func applicationDidFinishLaunching(_ n: Notification) {
        model.start()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = NAME
        window.isReleasedWhenClosed = false
        // a hosting controller keeps the content below the title bar (v9: with a bare NSHostingView the ON / OFF row
        // sat under it and was cut off at the top)
        window.contentViewController = NSHostingController(rootView: Panel(m: model) { [weak self] in self?.window.orderOut(nil) })
        // sized from the screen it opens on (MANTRA_MANIFEST two-screens.md): never taller than its visible frame
        let vis = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        window.setContentSize(NSSize(width: 460, height: min(900, vis.height - 60)))
        window.minSize = NSSize(width: 460, height: 420)
        window.center()
        window.appearance = NSAppearance(named: .darkAqua)
        if !CommandLine.arguments.contains("--login") { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }
}

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let d = AppDelegate()
        app.delegate = d
        app.setActivationPolicy(.regular)
        app.run()
    }
}
