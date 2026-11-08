import AppKit
import CryptoKit

/// CLASSROOM, the third profile (Marko, 8.11.2026, request 11: "the profile to control my video ninja session ... switch
/// all the views, layouts ... with the identical icons ... Plus controlling each participants. Separately ... noise
/// reduction and Canceling ... also the mute for microphones for every participant").
///
/// It is the MPA Academy remote page (mpa-academy.pages.dev/portal/remote?s=natasha-27de) on the deck: it joins the
/// classroom's signalling as the teacher's invisible remote (rc=1), sees everyone, and sends each change to one person
/// only, the same messages the remote page sends ("set-audio" with `to`); the person's own answer ("audio-state") lights
/// the keys. The teacher's sign-in is signed here with ~/.mpa/session_secret (read each time, never stored or shown).
///
///   row 1   the five layouts of the classroom, the page's own pictures (green = me, orange = the other),
///           for the person whose name key is lit
///   row 2   the host:   NAME (choose for the layouts) · MIC (mute) · ECHO CANCEL · NOISE REDUCTION · CAMERA
///   row 3   the guest:  the same
final class Classroom: NSObject, URLSessionWebSocketDelegate {
    static let host = "mpa-academy.pages.dev"
    static let layouts: [(String, String)] = [("split", "SPLIT"), ("pip", "OTHER BIG"), ("pipme", "ME BIG"),
                                              ("them", "OTHER"), ("me", "ME")]
    var onChange: () -> Void = {}

    let room = UserDefaults.standard.string(forKey: "classroom") ?? "natasha-27de"
    private(set) var connected = false
    private(set) var problem = ""
    private var people: [String: [String: Any]] = [:]     // id → card + "st" (its audio-state)
    private var order: [String] = []
    private var target = ""                                // whose layout row 1 changes
    private var task: URLSessionWebSocketTask?
    private var session: URLSession!
    private var retry = 0
    private var pics: [String: [String: Any]] = [:]       // icon id → key, for the phone's /icon

    func start() {
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        connect()
        Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in self?.send(["t": "ping"]) }
    }

    // MARK: the line to the classroom

    private func cookie() -> String? {
        let f = NSHomeDirectory() + "/.mpa/session_secret"
        guard let s = try? String(contentsOfFile: f, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        let enc = { (x: String) in x.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.!~*'()"))) ?? x }
        let until = String(Int(Date().timeIntervalSince1970 * 1000) + 12 * 3600 * 1000)
        let body = ["marko.bosko@auroville.community", "admin", "", until].map(enc).joined(separator: "|")
        let mac = HMAC<SHA256>.authenticationCode(for: Data(body.utf8), using: SymmetricKey(data: Data(s.utf8)))
        return body + "|" + mac.map { String(format: "%02x", $0) }.joined()
    }

    private func connect() {
        guard let c = cookie() else { problem = "No ~/.mpa/session_secret on this Mac"; onChange(); return }
        guard let url = URL(string: "wss://\(Classroom.host)/api/room/\(room)?rc=1&d=rc-deck") else { return }
        var r = URLRequest(url: url)
        r.setValue("mpa=" + c, forHTTPHeaderField: "Cookie")
        let t = session.webSocketTask(with: r)
        task = t
        t.resume()
        receive(t)
    }

    private func again() {
        task = nil; connected = false; onChange()
        let wait = min(pow(2, Double(retry)), 15); retry += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in if self?.task == nil { self?.connect() } }
    }

    func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask, didOpenWithProtocol p: String?) {
        guard t === task else { return }
        connected = true; retry = 0; problem = ""; onChange()
    }

    func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask, didCloseWith c: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if t === task { again() }
    }

    private func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self, t === self.task else { return }
                switch r {
                case .failure(let e): self.problem = e.localizedDescription; self.again()
                case .success(let m):
                    if case .string(let s) = m, let j = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] {
                        self.handle(j)
                    }
                    self.receive(t)
                }
            }
        }
    }

    private func send(_ o: [String: Any]) {
        guard connected, let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }

    private func handle(_ m: [String: Any]) {
        let t = m["t"] as? String ?? ""
        switch t {
        case "welcome":
            people = [:]
            for p in m["peers"] as? [[String: Any]] ?? [] { if let id = p["id"] as? String { people[id] = p } }
            send(["t": "rc", "a": "hello"])
        case "joined":
            if let p = m["peer"] as? [String: Any], let id = p["id"] as? String { people[id] = p }
        case "left":
            if let id = m["id"] as? String { people[id] = nil }
        case "audio-state":
            if let id = m["from"] as? String, people[id] != nil { people[id]?["st"] = m }
        case "replaced":
            problem = "The deck's remote was opened somewhere else"
        default: return
        }
        // the host first, then the guest (as the remote page orders them)
        order = people.values.sorted { a, b in
            ((a["role"] as? String) == "admin" ? 0 : 1, a["id"] as? String ?? "") < ((b["role"] as? String) == "admin" ? 0 : 1, b["id"] as? String ?? "")
        }.compactMap { $0["id"] as? String }
        if !order.contains(target) { target = order.last ?? "" }   // the guest by default
        onChange()
    }

    // MARK: the keys

    private func st(_ id: String) -> [String: Any] { people[id]?["st"] as? [String: Any] ?? [:] }

    private func shortName(_ p: [String: Any]) -> String {
        if (p["role"] as? String) == "admin" { return "Mantreshwar" }
        let n = (p["name"] as? String ?? ""), who = p["who"] as? String ?? ""
        let s = (!n.isEmpty && !n.contains("@")) ? n : String(who.split(separator: "@").first ?? "")
        return String(s.split(whereSeparator: { " ._-".contains($0) }).first ?? "?")
    }

    func keys() -> [[String: Any]] {
        var k: [[String: Any]] = []
        let ts = st(target)
        for (v, name) in Classroom.layouts {
            k.append(["kind": "cls", "what": "lay", "v": v, "label": name,
                      "active": !target.isEmpty && (ts["lay"] as? String) == v, "on": !target.isEmpty && !ts.isEmpty])
        }
        for row in 0..<2 {
            guard row < order.count, let p = people[order[row]] else {
                k.append(["kind": "cls", "what": "nobody", "label": row == 0 ? "HOST" : "GUEST"])
                for _ in 0..<4 { k.append(["kind": "empty"]) }
                continue
            }
            let id = order[row], s = st(id), has = !s.isEmpty
            k.append(["kind": "cls", "what": "name", "label": shortName(p), "role": (p["role"] as? String) == "admin" ? "HOST" : "GUEST",
                      "active": id == target, "id": id])
            for w in ["mic", "ec", "ns", "cam"] {
                k.append(["kind": "cls", "what": w, "id": id, "active": s[w] as? Bool ?? false, "on": has])
            }
        }
        // the phone fetches each picture by an id that changes with what it shows
        pics = [:]
        return k.map { key in
            guard key["kind"] as? String == "cls" else { return key }
            var key = key
            let sig = ["what", "v", "label", "role", "active", "on"].map { "\(key[$0] ?? "")" }.joined(separator: ".")
            let id = "cls:" + Insecure.MD5.hash(data: Data(sig.utf8)).map { String(format: "%02x", $0) }.joined()
            key["icon"] = id
            pics[id] = key
            return key
        }
    }

    var title: String { room == "natasha-27de" ? "Natasha’s classroom" : room }
    var note: String {
        if !problem.isEmpty { return problem }
        if !connected { return "Connecting to the classroom…" }
        if order.isEmpty { return "Nobody in the classroom yet" }
        let n = order.compactMap { people[$0].map(shortName) }.joined(separator: " · ")
        return "\(n) · layouts for \(people[target].map(shortName) ?? "—")"
    }

    func press(_ i: Int) {
        let k = keys()
        guard (0..<k.count).contains(i), k[i]["kind"] as? String == "cls" else { return }
        let what = k[i]["what"] as? String ?? ""
        switch what {
        case "lay":
            guard !target.isEmpty, let v = k[i]["v"] as? String else { return }
            setState(target, "lay", v)
        case "name":
            target = k[i]["id"] as? String ?? target
            onChange()
        case "mic", "ec", "ns", "cam":
            guard let id = k[i]["id"] as? String, !st(id).isEmpty else { return }
            setState(id, what, !(st(id)[what] as? Bool ?? false))
        default: break
        }
    }

    /// Shown at once; the person's own answer follows and wins (as on the remote page).
    private func setState(_ id: String, _ k: String, _ v: Any) {
        var s = st(id); s[k] = v; people[id]?["st"] = s
        send(["t": "set-audio", "k": k, "v": v, "to": id])
        onChange()
    }

    /// The phone's picture of a key: the same drawing as the real deck, 144 px.
    func png(_ id: String) -> Data? {
        guard let k = pics[id] else { return nil }
        let (rep, _) = KeyArt.draw(k, size: 144)
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: drawing (the remote page's look: amber #F59E0B on, green #3fb950 = me, orange = the other)

    static let amber = NSColor(red: 0xF5 / 255.0, green: 0x9E / 255.0, blue: 0x0B / 255.0, alpha: 1)
    static let mpaGreen = NSColor(red: 0x3F / 255.0, green: 0xB9 / 255.0, blue: 0x50 / 255.0, alpha: 1)
    static let red = NSColor(red: 0xEF / 255.0, green: 0x44 / 255.0, blue: 0x44 / 255.0, alpha: 1)
    static let dim = NSColor(white: 0.55, alpha: 1)

    /// Draws one CLASSROOM key in a 72-unit square (u = points per unit, y up).
    static func draw(_ k: [String: Any], u: CGFloat) {
        let what = k["what"] as? String ?? "", active = k["active"] as? Bool ?? false, on = k["on"] as? Bool ?? true
        let label = k["label"] as? String ?? ""
        func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * u, y: y * u, width: w * u, height: h * u) }
        func text(_ t: String, _ pt: CGFloat, _ y: CGFloat, _ c: NSColor, _ w: NSFont.Weight = .bold) {
            let p = NSMutableParagraphStyle(); p.alignment = .center; p.lineBreakMode = .byTruncatingTail
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: pt * u, weight: w), .foregroundColor: c,
                                                    .paragraphStyle: p, .kern: 0.6 * u]
            (t as NSString).draw(in: R(2, y, 68, pt * 1.35), withAttributes: a)
        }
        switch what {
        case "lay":
            // the page's square: black, a thin light rim; amber = the other, green = me; the chosen one ringed white
            let sq = R(13, 19, 46, 46)
            let o = amber.withAlphaComponent(on ? 1 : 0.35), g = mpaGreen.withAlphaComponent(on ? 1 : 0.35)
            NSColor.black.setFill(); sq.fill()
            let v = k["v"] as? String ?? ""
            let small = R(13 + 46 - 3 - 18.4, 19 + 3, 18.4, 18.4)
            switch v {
            case "split": o.setFill(); R(13, 19, 22.5, 46).fill(); g.setFill(); R(36.5, 19, 22.5, 46).fill()
            case "pip": o.setFill(); sq.fill(); NSColor.black.setFill(); small.insetBy(dx: -u, dy: -u).fill(); g.setFill(); small.fill()
            case "pipme": g.setFill(); sq.fill(); NSColor.black.setFill(); small.insetBy(dx: -u, dy: -u).fill(); o.setFill(); small.fill()
            case "them": o.setFill(); sq.fill()
            default: g.setFill(); sq.fill()
            }
            NSColor(white: 1, alpha: 0.25).setStroke(); let b = NSBezierPath(rect: sq); b.lineWidth = u; b.stroke()
            if active { NSColor.white.setStroke(); let r = NSBezierPath(rect: sq.insetBy(dx: -3 * u, dy: -3 * u)); r.lineWidth = 2 * u; r.stroke() }
            text(label, 8.5, 3, active ? .white : dim)
        case "name":
            if active {
                mpaGreen.setStroke()
                let r = NSBezierPath(roundedRect: R(2, 2, 68, 68), xRadius: 8 * u, yRadius: 8 * u); r.lineWidth = 3 * u; r.stroke()
            }
            text(label.uppercased(), label.count > 8 ? 10.5 : 13, 33, active ? .white : NSColor(white: 0.85, alpha: 1))
            text(k["role"] as? String ?? "", 9, 19, active ? mpaGreen : dim, .semibold)
            text(active ? "LAYOUT ▲" : "", 8, 6, mpaGreen, .semibold)
        case "nobody":
            text(label, 10, 33, NSColor(white: 0.35, alpha: 1))
            text("not here", 8.5, 20, NSColor(white: 0.35, alpha: 1), .regular)
        case "mic", "cam":
            // the page's round button: amber when on; off = dark with a red stroke through it (muted)
            let c = R(16, 24, 40, 40)
            let path = NSBezierPath(ovalIn: c)
            if active && on { amber.setFill(); path.fill() } else { NSColor(white: 1, alpha: 0.08).setFill(); path.fill()
                NSColor(white: 1, alpha: 0.25).setStroke(); path.lineWidth = u; path.stroke() }
            let ink = active && on ? NSColor(red: 0x0B / 255.0, green: 0x0D / 255.0, blue: 0x10 / 255.0, alpha: 1) : NSColor(white: 1, alpha: on ? 0.75 : 0.3)
            glyph(what, in: c.insetBy(dx: 9 * u, dy: 9 * u), color: ink, u: u)
            if !active && on {
                red.setStroke(); let s = NSBezierPath(); s.move(to: NSPoint(x: c.minX + 8 * u, y: c.minY + 8 * u))
                s.line(to: NSPoint(x: c.maxX - 8 * u, y: c.maxY - 8 * u)); s.lineWidth = 3 * u; s.lineCapStyle = .round; s.stroke()
            }
            let word = what == "mic" ? (active ? "MIC ON" : "MUTED") : (active ? "CAMERA" : "CAM OFF")
            text(on ? word : "—", 9, 5, !on ? dim : (active ? amber : red))
        case "ec", "ns":
            // the page's switch: a pill, amber with the dark knob on the right when on
            let pill = R(18, 44, 36, 18)
            let p = NSBezierPath(roundedRect: pill, xRadius: 9 * u, yRadius: 9 * u)
            if active && on { amber.setFill() } else { NSColor(white: 1, alpha: 0.15).setFill() }
            p.fill()
            let knob = NSBezierPath(ovalIn: active ? R(37.5, 46, 14, 14) : R(20.5, 46, 14, 14))
            (active && on ? NSColor(red: 0x0B / 255.0, green: 0x0D / 255.0, blue: 0x10 / 255.0, alpha: 1) : NSColor(white: 0.7, alpha: 1)).setFill(); knob.fill()
            let (a, b) = what == "ec" ? ("ECHO", "CANCEL") : ("NOISE", "REDUCTION")
            let c = !on ? dim : (active ? .white : NSColor(white: 0.7, alpha: 1))
            text(a, 10.5, 22, c); text(b, b.count > 7 ? 8.5 : 10.5, 9, c)
        default: break
        }
    }

    /// The page's microphone and camera icons (24-unit SVG paths), drawn in r.
    private static func glyph(_ what: String, in r: NSRect, color: NSColor, u: CGFloat) {
        let s = r.width / 24
        func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: r.minX + x * s, y: r.maxY - y * s) }
        let p = NSBezierPath(); p.lineWidth = 2 * s; p.lineCapStyle = .round; p.lineJoinStyle = .round
        color.setStroke()
        if what == "mic" {
            p.appendRoundedRect(NSRect(x: P(9, 15).x, y: P(9, 15).y, width: 6 * s, height: 12 * s), xRadius: 3 * s, yRadius: 3 * s)
            p.move(to: P(5, 11)); p.curve(to: P(19, 11), controlPoint1: P(5, 20.5), controlPoint2: P(19, 20.5))
            p.move(to: P(12, 18)); p.line(to: P(12, 21))
        } else {
            p.move(to: P(4, 8)); p.line(to: P(7, 8)); p.line(to: P(9, 5)); p.line(to: P(15, 5)); p.line(to: P(17, 8))
            p.line(to: P(20, 8)); p.line(to: P(21, 9)); p.line(to: P(21, 18)); p.line(to: P(20, 19)); p.line(to: P(4, 19))
            p.line(to: P(3, 18)); p.line(to: P(3, 9)); p.close()
            p.appendOval(in: NSRect(x: P(8.5, 16.5).x, y: P(8.5, 16.5).y, width: 7 * s, height: 7 * s))
        }
        p.stroke()
    }
}
