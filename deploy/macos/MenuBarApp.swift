import Cocoa
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let label = "it.bruens.meridian-tunnel-menubar"
    private let appSupport = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/Meridian Tunnel"
    private let logs = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Logs"
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let stateItem = NSMenuItem(title: "Checking…", action: nil, keyEquivalent: "")
    private let detailItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let lastItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var timer: Timer?

    private var config: [String: String] = [:]
    private var base: String { config["MERIDIAN_INSTALL_DIR"] ?? appSupport }
    private var localHost: String { config["MERIDIAN_LOCAL_HOST"] ?? "127.0.0.1" }
    private var apiPort: String { config["MERIDIAN_LOCAL_API_PORT"] ?? "3456" }
    private var dashboardPort: String { config["MERIDIAN_DASHBOARD_PROXY_PORT"] ?? "3457" }
    private var apiBaseURL: String { "http://\(localHost):\(apiPort)" }
    private var dashboardBaseURL: String { "http://\(localHost):\(dashboardPort)" }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSApp.terminate(nil)
            return
        }

        loadConfig()
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⏳ Meridian"
        statusItem.button?.toolTip = "Meridian tunnel status"

        stateItem.isEnabled = false
        detailItem.isEnabled = false
        lastItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(detailItem)
        menu.addItem(lastItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Telemetry Dashboard", action: #selector(openTelemetry), keyEquivalent: "t"))
        menu.addItem(NSMenuItem(title: "Open Meridian Health JSON", action: #selector(openHealth), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Start / Restart Tunnel", action: #selector(restartTunnel), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Stop Tunnel", action: #selector(stopTunnel), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Refresh Status", action: #selector(refreshNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Tunnel Logs", action: #selector(openLogs), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Open Tunnel Folder", action: #selector(openTunnelFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Status App", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
        checkStatus()
    }

    @objc private func openTelemetry() {
        NSWorkspace.shared.open(URL(string: dashboardBaseURL + "/telemetry")!)
    }

    @objc private func openHealth() {
        NSWorkspace.shared.open(URL(string: apiBaseURL + "/health")!)
    }

    @objc private func restartTunnel() {
        setTransient("⏳ Meridian", state: "Restarting tunnel…", detail: "Running restart.sh")
        runShell("\"\(base)/restart.sh\"") { [weak self] _, _ in
            self?.checkStatus()
        }
    }

    @objc private func stopTunnel() {
        setTransient("⏳ Meridian", state: "Stopping tunnel…", detail: "Running stop.sh")
        runShell("\"\(base)/stop.sh\"") { [weak self] _, _ in
            self?.checkStatus()
        }
    }

    @objc private func refreshNow() {
        loadConfig()
        checkStatus()
    }

    @objc private func openLogs() {
        for name in ["meridian-tunnel.err.log", "meridian-tunnel.log", "meridian-dashboard-proxy.err.log", "meridian-tunnel-menubar.err.log"] {
            let url = URL(fileURLWithPath: logs + "/" + name)
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func openTunnelFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: base))
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func loadConfig() {
        let path = appSupport + "/config.env"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        var next: [String: String] = [:]
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || !line.contains("=") { continue }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                next[key] = value
            }
        }
        config = next
    }

    private func setTransient(_ button: String, state: String, detail: String) {
        DispatchQueue.main.async {
            self.statusItem.button?.title = button
            self.stateItem.title = state
            self.detailItem.title = detail
            self.lastItem.title = "Last update: \(Self.timeString())"
        }
    }

    private func checkStatus() {
        DispatchQueue.main.async {
            self.statusItem.button?.title = "⏳ Meridian"
            self.stateItem.title = "Checking tunnel…"
            self.detailItem.title = self.apiBaseURL
        }

        var req = URLRequest(url: URL(string: apiBaseURL + "/health")!)
        req.timeoutInterval = 2.5
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let http = response as? HTTPURLResponse, http.statusCode == 200, let data = data {
                let text = String(data: data, encoding: .utf8) ?? ""
                let loggedIn = text.contains("\"loggedIn\":true") || text.contains("\"loggedIn\": true")
                let mode = self.extractJSONValue(named: "mode", from: text) ?? "unknown"
                let version = self.extractJSONValue(named: "version", from: text) ?? "unknown"
                DispatchQueue.main.async {
                    self.statusItem.button?.title = loggedIn ? "🟢 Meridian" : "🟡 Meridian"
                    self.stateItem.title = loggedIn ? "Tunnel healthy" : "Tunnel reachable, not logged in"
                    self.detailItem.title = "Meridian \(version), mode=\(mode)"
                    self.lastItem.title = "Last update: \(Self.timeString())"
                }
                return
            }
            self.classifyPortAfterHealthFailure(error: error)
        }.resume()
    }

    private func classifyPortAfterHealthFailure(error: Error?) {
        runShell("/usr/sbin/lsof -nP -iTCP:\(apiPort) -sTCP:LISTEN 2>/dev/null || true") { [weak self] _, output in
            guard let self = self else { return }
            let lower = output.lowercased()
            let button: String
            let state: String
            let detail: String
            if lower.contains("ssh") {
                button = "🟡 Meridian"
                state = "SSH tunnel is listening, health failed"
                detail = error?.localizedDescription ?? "Health endpoint did not respond"
            } else if lower.contains("com.docke") || lower.contains("docker") {
                button = "🔴 Meridian"
                state = "Port \(self.apiPort) is used by local Docker"
                detail = "Run Start / Restart Tunnel to stop local Docker and reconnect"
            } else if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                button = "🔴 Meridian"
                state = "Tunnel down"
                detail = error?.localizedDescription ?? "No listener on \(self.localHost):\(self.apiPort)"
            } else {
                button = "🔴 Meridian"
                state = "Port \(self.apiPort) used by another process"
                detail = output.components(separatedBy: .newlines).dropFirst().first ?? "Unknown process"
            }
            DispatchQueue.main.async {
                self.statusItem.button?.title = button
                self.stateItem.title = state
                self.detailItem.title = detail
                self.lastItem.title = "Last update: \(Self.timeString())"
            }
        }
    }

    private func extractJSONValue(named key: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\\"" + NSRegularExpression.escapedPattern(for: key) + "\\\"\\s*:\\s*\\\"([^\\\"]+)\\\"") else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private func runShell(_ command: String, completion: @escaping (Int32, String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-lc", command]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async { completion(process.terminationStatus, output) }
            } catch {
                DispatchQueue.main.async { completion(127, error.localizedDescription) }
            }
        }
    }

    private static func timeString() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: Date())
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
