import SwiftUI
import AppKit

struct MenuPanel: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var vpn: VPNController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 14) {
            header
            Divider()
            if vpn.helper == .notInstalled || vpn.helper == .outdated {
                helperBanner
            }
            if store.profiles.isEmpty {
                emptyState
            } else {
                profilePicker
                mainButton
            }
            if !vpn.progress.isEmpty && vpn.isBusy {
                Text(vpn.progress).font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let err = vpn.lastError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: sections

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(statusColor.opacity(0.18)).frame(width: 44, height: 44)
                LampSymbol(look: lampLook, size: 30)
                    .foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle).font(.headline).lineLimit(1)
                Text(statusDetail).font(.subheadline).foregroundStyle(.secondary)
                    .monospacedDigit().lineLimit(1)
            }
            Spacer()
        }
    }

    private var helperBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vpn.helper == .outdated ? "The Passage helper needs an update." :
                    "Passage needs a one-time helper install so it can connect without asking for your password.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Button(vpn.helper == .outdated ? "Update Helper…" : "Install Helper…") { vpn.installHelper() }
                .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No VPN connections yet").foregroundStyle(.secondary)
            Button("Add Connection…") { openSettings() }
        }
        .frame(maxWidth: .infinity)
    }

    private var profilePicker: some View {
        Picker("Connection", selection: $store.selectedID) {
            ForEach(store.profiles) { p in Text(p.name).tag(p.id) }
        }
        .labelsHidden()
        .disabled(vpn.state != .disconnected)
    }

    private var mainButton: some View {
        Button {
            if vpn.connectedID != nil { vpn.disconnect() }
            else if let p = store.selected { vpn.connect(p) }
        } label: {
            HStack {
                if vpn.isBusy { ProgressView().controlSize(.small) }
                Text(buttonTitle).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(vpn.connectedID != nil ? .red : .green)
        .controlSize(.large)
        .disabled(vpn.isBusy || (vpn.connectedID == nil && vpn.helper != .ready))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Toggle("Open at login", isOn: Binding(get: { vpn.launchAtLogin }, set: { vpn.setLaunchAtLogin($0) }))
                .toggleStyle(.switch).controlSize(.small)
            Toggle(vpn.biometricsAvailable ? "Require Touch ID to connect" : "Require Mac password to connect",
                   isOn: $vpn.requireTouchID)
                .toggleStyle(.switch).controlSize(.small)
            HStack {
                Button("Settings…") { openSettings() }
                Button("Logs") { vpn.openLogs() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: text & colors

    private var statusColor: Color {
        switch vpn.state {
        case .connected: .green
        case .connecting, .disconnecting: .orange
        case .disconnected: .secondary
        }
    }

    private var lampLook: LampIcon.Look {
        switch vpn.state {
        case .connected: .lit
        case .connecting, .disconnecting: .dim
        case .disconnected: .off
        }
    }

    private var statusTitle: String {
        switch vpn.state {
        case .connected(let id, _, _): "Connected to \(store.profile(id)?.name ?? "VPN")"
        case .connecting: "Connecting to \(store.selected?.name ?? "VPN")…"
        case .disconnecting: "Disconnecting…"
        case .disconnected: "Not connected"
        }
    }

    private var statusDetail: String {
        switch vpn.state {
        case .connected(_, let ip, let since):
            let s = max(0, Int(vpn.now.timeIntervalSince(since)))
            return "\(ip) · " + String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
        case .connecting, .disconnecting: return ""
        case .disconnected: return "Passage"
        }
    }

    private var buttonTitle: String {
        switch vpn.state {
        case .connected: "Disconnect"
        case .connecting: "Connecting…"
        case .disconnecting: "Disconnecting…"
        case .disconnected: "Connect"
        }
    }
}

struct MenuBarIcon: View {
    @ObservedObject var vpn: VPNController
    var body: some View {
        switch vpn.state {
        case .connected: Image(nsImage: LampIcon.image(.lit))
        case .connecting, .disconnecting: Image(nsImage: LampIcon.image(.dim))
        case .disconnected: Image(nsImage: LampIcon.image(.off))
        }
    }
}

/// The lamp at any size. Off and dim follow the view's foreground color.
struct LampSymbol: View {
    let look: LampIcon.Look
    let size: CGFloat
    var body: some View {
        Image(nsImage: LampIcon.image(look))
            .renderingMode(look == .lit ? .original : .template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// The menu bar lamp post. Off and dim are template images, so macOS colors them to
/// match the menu bar. Lit draws a yellow lantern, and resolves the post's color
/// when drawn so it suits light and dark menu bars.
enum LampIcon {
    enum Look { case off, dim, lit }

    private static var cache: [Look: NSImage] = [:]

    static func image(_ look: Look) -> NSImage {
        if let img = cache[look] { return img }
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            draw(look); return true
        }
        img.isTemplate = look != .lit
        img.accessibilityDescription = look == .lit ? "Passage: connected" : "Passage"
        cache[look] = img
        return img
    }

    private static func draw(_ look: Look) {
        let ink = look == .lit ? NSColor.labelColor : NSColor.black
        let light = NSColor(srgbRed: 1.0, green: 0.78, blue: 0.24, alpha: 1)

        if look == .lit {
            // Glow and light rays around the lantern. The lamp shrinks a little
            // (around the base) so the rays fit in the 18pt icon.
            let scale: CGFloat = 0.9
            let c = NSPoint(x: 9, y: 11.8 * scale)
            NSGradient(colors: [light.withAlphaComponent(0.6), light.withAlphaComponent(0)])!
                .draw(fromCenter: c, radius: 0, toCenter: c, radius: 6.5, options: [])
            light.setStroke()
            for degrees in [0.0, 180.0, 40.0, 140.0] {
                let r = degrees * .pi / 180
                let ray = NSBezierPath()
                ray.lineWidth = 1.4; ray.lineCapStyle = .round
                ray.move(to: NSPoint(x: c.x + cos(r) * 4.8, y: c.y + sin(r) * 4.8))
                ray.line(to: NSPoint(x: c.x + cos(r) * 7.8, y: c.y + sin(r) * 7.8))
                ray.stroke()
            }
            let t = NSAffineTransform()
            t.translateX(by: 9, yBy: 0); t.scale(by: scale); t.translateX(by: -9, yBy: 0)
            t.concat()
        }

        ink.setFill()
        NSBezierPath(roundedRect: NSRect(x: 6, y: 0.5, width: 6, height: 2), xRadius: 0.6, yRadius: 0.6).fill()  // base
        NSBezierPath(rect: NSRect(x: 8.25, y: 2.5, width: 1.5, height: 6)).fill()                                // post
        NSBezierPath(rect: NSRect(x: 5.5, y: 6.2, width: 7, height: 1)).fill()                                   // crossbar
        NSBezierPath(rect: NSRect(x: 7, y: 8.2, width: 4, height: 1.2)).fill()                                   // collar

        // Lantern glass (tapered) and roof
        let glass = NSBezierPath()
        glass.move(to: NSPoint(x: 7.2, y: 9.4)); glass.line(to: NSPoint(x: 10.8, y: 9.4))
        glass.line(to: NSPoint(x: 11.8, y: 14.2)); glass.line(to: NSPoint(x: 6.2, y: 14.2)); glass.close()
        switch look {
        case .lit: light.setFill(); glass.fill()
        case .dim: NSColor.black.withAlphaComponent(0.45).setFill(); glass.fill()
        case .off: break
        }
        ink.setStroke(); glass.lineWidth = 1.1; glass.stroke()

        ink.setFill()
        let roof = NSBezierPath()
        roof.move(to: NSPoint(x: 5.4, y: 14.2)); roof.line(to: NSPoint(x: 12.6, y: 14.2))
        roof.line(to: NSPoint(x: 9.7, y: 16.4)); roof.line(to: NSPoint(x: 8.3, y: 16.4)); roof.close(); roof.fill()
        NSBezierPath(ovalIn: NSRect(x: 8.2, y: 16.2, width: 1.6, height: 1.6)).fill()                            // finial
    }
}
