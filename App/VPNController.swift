import Foundation
import AppKit
import ServiceManagement
import LocalAuthentication

/// Talks to the privileged helper over its Unix socket.
enum HelperClient {
    static let socketPath = "/var/run/passage.sock"
    static let expectedVersion = "7"

    struct Failure: Error { let message: String }

    static var socketExists: Bool { FileManager.default.fileExists(atPath: socketPath) }

    /// Sends a request and returns the final "ok:" text. Calls `progress` for "info:" lines.
    static func send(_ request: String, timeout: Int = 90,
                     progress: @escaping @Sendable (String) -> Void = { _ in }) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure(message: "socket failed") }
        defer { close(fd) }

        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketPath.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in path.enumerated() where i < buf.count - 1 { buf[i] = b }
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else { throw Failure(message: "Can't reach the Passage helper. Is it installed?") }

        let out = Array(request.utf8)
        var off = 0
        while off < out.count {
            let n = out[off...].withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
            guard n > 0 else { throw Failure(message: "Lost connection to the helper") }
            off += n
        }

        var buffer: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        var result: String?
        while true {
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            while let nl = buffer.firstIndex(of: 10) {
                let line = String(decoding: buffer[..<nl], as: UTF8.self)
                buffer.removeSubrange(...nl)
                if line.hasPrefix("info: ") { progress(String(line.dropFirst(6))) }
                else if line.hasPrefix("ok: ") { result = String(line.dropFirst(4)) }
                else if line.hasPrefix("error: ") { throw Failure(message: String(line.dropFirst(7))) }
            }
        }
        guard let r = result else { throw Failure(message: "The helper stopped without answering (timed out?)") }
        return r
    }
}

@MainActor
final class VPNController: ObservableObject {
    enum State: Equatable {
        case disconnected
        case connecting
        case disconnecting
        case connected(id: String, ip: String, since: Date)
    }

    enum HelperState: Equatable { case checking, notInstalled, outdated, ready }

    @Published var state: State = .disconnected
    @Published var helper: HelperState = .checking
    @Published var progress = ""
    @Published var lastError: String?
    @Published var now = Date()
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var requireTouchID = UserDefaults.standard.bool(forKey: "requireTouchID") {
        didSet { UserDefaults.standard.set(requireTouchID, forKey: "requireTouchID") }
    }

    /// Whether this Mac can do Touch ID (or a paired Apple Watch).
    var biometricsAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    private var timer: Timer?
    private var ticks = 0

    init() {
        checkHelper()
        refreshStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        now = Date()
        ticks += 1
        if ticks % 2 == 0 { refreshStatus() }
        if ticks % 30 == 0, helper != .ready { checkHelper() }
    }

    var isBusy: Bool { state == .connecting || state == .disconnecting }
    var connectedID: String? { if case .connected(let id, _, _) = state { id } else { nil } }

    // MARK: status

    /// The helper writes a world-readable status file; reading it needs no request.
    func refreshStatus() {
        guard !isBusy else { return }
        guard let text = try? String(contentsOfFile: "/var/run/passage.status", encoding: .utf8) else {
            state = .disconnected; return
        }
        var kv: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { kv[parts[0]] = parts[1] }
        }
        guard let id = kv["id"], let ifname = kv["ifname"], let ip = kv["ip"],
              let since = TimeInterval(kv["since"] ?? ""), Self.interfaceExists(ifname) else {
            state = .disconnected; return
        }
        state = .connected(id: id, ip: ip, since: Date(timeIntervalSince1970: since))
    }

    private static func interfaceExists(_ name: String) -> Bool {
        if_nametoindex(name) != 0
    }

    func checkHelper() {
        guard HelperClient.socketExists else { helper = .notInstalled; return }
        Task.detached {
            let v = try? HelperClient.send("cmd=version\n\n", timeout: 5)
            await MainActor.run {
                if v == nil { self.helper = .notInstalled }
                else if v == HelperClient.expectedVersion { self.helper = .ready }
                else { self.helper = .outdated }
            }
        }
    }

    // MARK: connect / disconnect

    func connect(_ profile: Profile) {
        lastError = nil
        if let first = profile.problems.first { lastError = first; return }
        guard helper == .ready else { lastError = "Install the helper first"; return }
        guard requireTouchID else { startConnect(profile); return }

        // Touch ID, falling back to the Mac password if Touch ID isn't available.
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "connect to \(profile.name)") { ok, _ in
            Task { @MainActor in
                if ok { self.startConnect(profile) }
            }
        }
    }

    private func startConnect(_ profile: Profile) {

        // Saved secrets stay with the helper; the app only sends a password you type now.
        let saved = Secrets.status(profile)
        var password = ""
        if profile.askPasswordEachTime || !saved.password {
            guard let p = Self.askPassword(for: profile) else { return }
            password = p
        }
        if profile.ipsecEnabled && !saved.psk {
            lastError = "Add the IPsec pre-shared key in Settings"; return
        }

        state = .connecting
        progress = "Starting…"
        let request = profile.helperRequest(password: password, psk: "")
        Task.detached {
            do {
                _ = try HelperClient.send(request) { line in
                    Task { @MainActor in self.progress = line }
                }
                await MainActor.run { self.finish(nil) }
            } catch let e as HelperClient.Failure {
                await MainActor.run { self.finish(e.message) }
            } catch {
                await MainActor.run { self.finish(error.localizedDescription) }
            }
        }
    }

    func disconnect() {
        lastError = nil
        state = .disconnecting
        progress = ""
        Task.detached {
            do {
                _ = try HelperClient.send("cmd=down\n\n", timeout: 30)
                await MainActor.run { self.finish(nil) }
            } catch let e as HelperClient.Failure {
                await MainActor.run { self.finish(e.message) }
            } catch {
                await MainActor.run { self.finish(error.localizedDescription) }
            }
        }
    }

    private func finish(_ error: String?) {
        state = .disconnected
        progress = ""
        lastError = error
        refreshStatus()
    }

    private static func askPassword(for p: Profile) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Password for \(p.name)"
        alert.informativeText = "Enter the VPN password for \(p.username)."
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return nil }
        return field.stringValue
    }

    // MARK: helper install

    /// Runs a bundled script as root via the standard macOS administrator prompt.
    private func runAsAdmin(_ script: String, args: String, prompt: String) {
        guard let path = Bundle.main.path(forResource: script, ofType: nil) else {
            lastError = "\(script) missing from app bundle"; return
        }
        let shell = "/bin/bash '\(path.replacingOccurrences(of: "'", with: "'\\''"))' \(args)"
        let apple = "do shell script \"\(shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with prompt \"\(prompt)\" with administrator privileges"
        helper = .checking
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", apple]
            let err = Pipe()
            p.standardError = err
            p.standardOutput = Pipe()
            try? p.run()
            p.waitUntilExit()
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            await MainActor.run {
                if p.terminationStatus != 0 && !msg.contains("User canceled") && !msg.contains("-128") {
                    self.lastError = msg.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                self.checkHelper()
            }
        }
    }

    func installHelper() {
        runAsAdmin("install-helper.sh", args: String(getuid()),
                   prompt: "Passage needs to install a helper to manage VPN connections.")
    }

    func uninstallHelper() {
        runAsAdmin("uninstall-helper.sh", args: "",
                   prompt: "Passage wants to remove its helper.")
    }

    // MARK: misc

    func openLogs() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/var/log/passage"))
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = "Couldn't change login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
