import AppKit
import CryptoKit

/// OBS, the second profile (Marko, 6.11.2026: "Needs to recognize when OBS is open. Which scenes are available? And
/// just create Icons, which are just simple numbers for each scene ... And then I can switch the scenes through my
/// phone."). OBS's own WebSocket server (obs-websocket v5, built into OBS 28+) on 127.0.0.1; its port and password are
/// read from OBS's own settings file each time it connects, so nothing is stored here and nothing is typed.
/// The scenes are numbered as OBS lists them, top first: key 1 is the top scene. The live (program) scene is green.
final class OBS: NSObject, URLSessionWebSocketDelegate {
    static let bundle = "com.obsproject.obs-studio"
    var onChange: () -> Void = {}

    private(set) var running = false
    private(set) var connected = false
    private(set) var scenes: [String] = []
    private(set) var current = ""
    private(set) var problem = ""
    private var page = 0
    private var task: URLSessionWebSocketTask?
    private var session: URLSession!
    private var password: String?
    private var nextId = 0
    private var watching: [NSObjectProtocol] = []

    func start() {
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            watching.append(nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.tick() })
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    /// Every 2 s and at every launch or quit: is OBS open, and is the line to it up?
    func tick() {
        let r = NSRunningApplication.runningApplications(withBundleIdentifier: OBS.bundle).contains { !$0.isTerminated }
        if r != running {
            running = r
            if !r { drop(""); scenes = []; current = "" }
            onChange()
        }
        if running && task == nil { connect() }
    }

    private struct Config { var port = 4455; var enabled = true; var auth = false; var password = "" }

    private func config() -> Config {
        var c = Config()
        let f = NSHomeDirectory() + "/Library/Application Support/obs-studio/plugin_config/obs-websocket/config.json"
        guard let d = FileManager.default.contents(atPath: f),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return c }
        c.port = j["server_port"] as? Int ?? 4455
        c.enabled = j["server_enabled"] as? Bool ?? true
        c.auth = j["auth_required"] as? Bool ?? false
        c.password = j["server_password"] as? String ?? ""
        return c
    }

    private func connect() {
        let c = config()
        guard c.enabled else {
            set(problem: "OBS's WebSocket server is off: in OBS, Tools → WebSocket Server Settings → Enable")
            return
        }
        password = c.auth ? c.password : nil
        guard let url = URL(string: "ws://127.0.0.1:\(c.port)") else { return }
        let t = session.webSocketTask(with: url)
        task = t
        t.resume()
        receive(t)
    }

    private func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self, t === self.task else { return }
                switch r {
                case .failure: self.drop(self.running ? "Waiting for OBS's WebSocket server…" : "")
                case .success(let m):
                    if case .string(let s) = m { self.handle(s) }
                    self.receive(t)
                }
            }
        }
    }

    private func drop(_ why: String) {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        let was = connected
        connected = false
        if was || why != problem { problem = why; onChange() }
    }

    private func set(problem p: String) { if p != problem { problem = p; onChange() } }

    func urlSession(_ s: URLSession, webSocketTask t: URLSessionWebSocketTask, didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard t === task else { return }
        // 4009: the password was refused
        drop(code.rawValue == 4009 ? "OBS refused the WebSocket password from its own settings" : "Waiting for OBS's WebSocket server…")
    }

    private func send(_ j: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: j), let s = String(data: d, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }

    private func request(_ type: String, _ data: [String: Any]? = nil) {
        nextId += 1
        var d: [String: Any] = ["requestType": type, "requestId": "\(nextId)"]
        if let data = data { d["requestData"] = data }
        send(["op": 6, "d": d])
    }

    private static func b64sha(_ s: String) -> String { Data(SHA256.hash(data: Data(s.utf8))).base64EncodedString() }

    private func handle(_ s: String) {
        guard let j = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any],
              let op = j["op"] as? Int, let d = j["d"] as? [String: Any] else { return }
        switch op {
        case 0:   // Hello → Identify, with the answer to the challenge when OBS asks for one; events: Scenes (1 << 2)
            var ident: [String: Any] = ["rpcVersion": 1, "eventSubscriptions": 1 << 2]
            if let a = d["authentication"] as? [String: Any], let ch = a["challenge"] as? String, let salt = a["salt"] as? String {
                let pw = password ?? config().password
                ident["authentication"] = OBS.b64sha(OBS.b64sha(pw + salt) + ch)
            }
            send(["op": 1, "d": ident])
        case 2:   // Identified
            connected = true
            problem = ""
            request("GetSceneList")
            onChange()
        case 5:   // an event
            let type = d["eventType"] as? String ?? ""
            let data = d["eventData"] as? [String: Any] ?? [:]
            if type == "CurrentProgramSceneChanged", let n = data["sceneName"] as? String {
                current = n; onChange()
            } else if ["SceneListChanged", "SceneCreated", "SceneRemoved", "SceneNameChanged"].contains(type) {
                request("GetSceneList")
            }
        case 7:   // a request's answer
            if d["requestType"] as? String == "GetSceneList", let rd = d["responseData"] as? [String: Any] {
                let list = rd["scenes"] as? [[String: Any]] ?? []
                // OBS gives the list bottom first (sceneIndex 0 is the lowest in its Scenes dock): turned, top first
                scenes = list.sorted { ($0["sceneIndex"] as? Int ?? 0) > ($1["sceneIndex"] as? Int ?? 0) }
                    .compactMap { $0["sceneName"] as? String }
                current = rd["currentProgramSceneName"] as? String ?? current
                onChange()
            }
        default: break
        }
    }

    // MARK: the keys

    private func layout() -> [[String: Any]] {
        if !running { return [["kind": "open", "label": "OPEN OBS", "icon": OBS.bundle]] + empty(14) }
        if !connected { return empty(15) }
        let paged = scenes.count > 15
        let per = paged ? 14 : 15
        let pages = max(1, (scenes.count + per - 1) / per)
        page = min(page, pages - 1)
        let first = page * per
        var k: [[String: Any]] = scenes.enumerated().dropFirst(first).prefix(per).map { i, n in
            ["kind": "scene", "label": "\(i + 1)", "active": n == current]
        }
        k += empty(per - k.count)
        if paged { k.append(["kind": "next", "label": "\(page + 1) / \(pages)"]) }
        return k
    }

    private func empty(_ n: Int) -> [[String: Any]] { [[String: Any]](repeating: ["kind": "empty"], count: max(0, n)) }

    var summary: String {
        if !running { return "OBS is not open" }
        if !connected { return problem.isEmpty ? "Connecting to OBS…" : problem }
        return "\(scenes.count) scenes · live: \(current)"
    }

    func fill(_ s: inout [String: Any]) {
        s["keys"] = layout()
        if !running { s["title"] = "OBS is not open"; s["note"] = "Key 1 opens it" }
        else if !connected { s["title"] = "OBS"; s["note"] = problem.isEmpty ? "Connecting to OBS…" : problem }
        else {
            let n = (scenes.firstIndex(of: current) ?? -1) + 1
            s["title"] = n > 0 ? "\(n) · \(current)" : current
            s["note"] = "OBS · \(scenes.count) scenes"
        }
    }

    func press(_ i: Int) {
        let k = layout()
        guard i >= 0, i < k.count else { return }
        switch k[i]["kind"] as? String {
        case "open":
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: OBS.bundle) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            }
        case "next":
            page += 1
            if page * 14 >= scenes.count { page = 0 }
            onChange()
        case "scene":
            let n = (Int(k[i]["label"] as? String ?? "") ?? 0) - 1
            guard n >= 0, n < scenes.count else { return }
            request("SetCurrentProgramScene", ["sceneName": scenes[n]])
        default: break
        }
    }
}
