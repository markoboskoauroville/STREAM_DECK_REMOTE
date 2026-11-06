import AppKit
import Network

/// The phone's line, HTTP on port 8963 (MANTRA_PORTS name `streamdeck-remote`), announced by Bonjour as
/// `_mantradeck._tcp` so the phone finds the Mac on the same Wi-Fi by itself, with no ADB and no address typed.
///   GET /hello                          {"name","version"}
///   GET /state?v=N                      the profile in use and its 15 keys, the same the real deck shows; held up to
///                                       8 s until something changes after version N; "presses"/"pressed" let the
///                                       phone enlarge the key the real deck enlarged
///   GET /press?key=i                    key i (0…14) pressed on the phone (the real deck enlarges it too)
///   GET /profile?p=apps|obs             the tab chosen on the phone: both faces change to it
///   GET /icon?id=<bundle id>            an app's icon, PNG
/// Only the home network, Tailscale and this Mac itself (adb reverse) are answered. macOS 15 holds back the home
/// Wi-Fi until Local Network is allowed for this app (MACOS_TASK_SWITCHER LESSONS, 26.10.2026).
let PORT: UInt16 = 8963

final class Server {
    let engine: Engine
    var onSeen: (String) -> Void = { _ in }
    private var listener: NWListener?
    private(set) var version = 1
    private var waiting: [(c: NWConnection, after: Int)] = []
    private(set) var state = "starting"
    let name = Host.current().localizedName ?? "Mac"

    init(engine: Engine) { self.engine = engine }

    func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: PORT),
              let l = try? NWListener(using: .tcp, on: port) else { state = "port \(PORT) is taken"; return }
        l.service = NWListener.Service(name: name, type: "_mantradeck._tcp")
        l.newConnectionHandler = { [weak self] c in self?.serve(c) }
        l.stateUpdateHandler = { [weak self] st in
            switch st {
            case .ready:
                self?.state = "listening on \(PORT)"
                Ports.record("streamdeck-remote", PORT, udp: false, health: "/hello")
            case .failed(let e):
                self?.state = "failed: \(e)"
                self?.listener = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.start() }
            default: break
            }
        }
        l.start(queue: .main)
        listener = l
    }

    func stop() { listener?.cancel(); listener = nil }

    /// Something changed (an app, OBS): every waiting phone is answered now.
    func changed() {
        version += 1
        let w = waiting
        waiting.removeAll()
        let body = json(state())
        for x in w { reply(x.c, body) }
    }

    private func state() -> [String: Any] {
        ["v": version, "profile": engine.profile, "mac": name, "keys": engine.keys(), "title": engine.title,
         "note": engine.note, "presses": engine.presses, "pressed": engine.lastPressed, "flash": engine.flashKey]
    }

    private func allowed(_ c: NWConnection) -> Bool {
        guard case let .hostPort(host, _) = c.endpoint else { return false }
        let ip = "\(host)".replacingOccurrences(of: "::ffff:", with: "").components(separatedBy: "%")[0]
        if ip == "127.0.0.1" || ip == "::1" { return true }
        let p = ip.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return false }
        return p[0] == 10 || (p[0] == 192 && p[1] == 168) || (p[0] == 172 && (16...31).contains(p[1]))
            || (p[0] == 100 && (64...127).contains(p[1]))
    }

    private func who(_ c: NWConnection) -> String {
        guard case let .hostPort(host, _) = c.endpoint else { return "?" }
        let ip = "\(host)".replacingOccurrences(of: "::ffff:", with: "").components(separatedBy: "%")[0]
        return ip == "127.0.0.1" || ip == "::1" ? "the cable (adb)" : ip
    }

    private func serve(_ c: NWConnection) {
        c.start(queue: .main)
        guard allowed(c) else { c.cancel(); return }
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self = self, let d = data, let text = String(data: d, encoding: .utf8),
                  let line = text.components(separatedBy: "\r\n").first else { c.cancel(); return }
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let u = URLComponents(string: String(parts[1])) else { c.cancel(); return }
            let q = { (n: String) in u.queryItems?.first { $0.name == n }?.value }
            self.onSeen(self.who(c))
            switch u.path {
            case "/hello":
                self.reply(c, self.json(["name": self.name, "version": VERSION]))
            case "/state":
                let after = Int(q("v") ?? "") ?? -1
                if after != self.version { self.reply(c, self.json(self.state())); return }
                self.waiting.append((c, after))
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                    guard let self = self, self.waiting.contains(where: { $0.c === c }) else { return }
                    self.waiting.removeAll { $0.c === c }
                    self.reply(c, self.json(self.state()))
                }
            case "/press":
                self.engine.press(Int(q("key") ?? "") ?? -1)
                self.reply(c, self.json(["ok": true]))
            case "/profile":
                self.engine.setProfile(q("p") ?? "")
                self.reply(c, self.json(["ok": true, "profile": self.engine.profile]))
            case "/icon":
                if let png = Apps.icon(q("id") ?? "") { self.reply(c, png, type: "image/png") }
                else { self.reply(c, Data("no icon".utf8), status: "404 Not Found", type: "text/plain") }
            default:
                self.reply(c, Data("no such thing".utf8), status: "404 Not Found", type: "text/plain")
            }
        }
    }

    private func json(_ j: [String: Any]) -> Data { (try? JSONSerialization.data(withJSONObject: j)) ?? Data("{}".utf8) }

    private func reply(_ c: NWConnection, _ body: Data, status: String = "200 OK", type: String = "application/json") {
        var out = Data("HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        out.append(body)
        c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
    }
}

/// The cable, or wireless ADB, when the Wi-Fi is not shared: every 5 s each phone adb sees gets
/// `adb reverse tcp:8963 tcp:8963`, so on the phone the Mac is at 127.0.0.1:8963. Nothing happens without adb.
final class Cable {
    private let adb = NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb"
    private(set) var phones: [String] = []
    var onChange: () -> Void = {}

    func start() {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    private func run(_ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: adb); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return "" }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: d, encoding: .utf8) ?? ""
    }

    private func tick() {
        guard FileManager.default.isExecutableFile(atPath: adb) else { return }
        DispatchQueue.global().async {
            let serials = self.run(["devices"]).split(separator: "\n").dropFirst().compactMap { l -> String? in
                let f = l.split(separator: "\t"); return f.count == 2 && f[1] == "device" ? String(f[0]) : nil
            }
            var names: [String] = []
            for s in serials {
                if !self.run(["-s", s, "reverse", "--list"]).contains("tcp:\(PORT)") {
                    _ = self.run(["-s", s, "reverse", "tcp:\(PORT)", "tcp:\(PORT)"])
                }
                let model = self.run(["-s", s, "shell", "getprop", "ro.product.model"]).trimmingCharacters(in: .whitespacesAndNewlines)
                names.append(model.isEmpty ? s : model)
            }
            DispatchQueue.main.async {
                if names != self.phones { self.phones = names; self.onChange() }
            }
        }
    }
}
