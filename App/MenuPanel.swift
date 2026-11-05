import SwiftUI

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
                Image(systemName: statusSymbol)
                    .font(.system(size: 20, weight: .semibold))
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

    private var statusSymbol: String {
        switch vpn.state {
        case .connected: "lock.shield.fill"
        case .connecting, .disconnecting: "arrow.triangle.2.circlepath"
        case .disconnected: "shield.slash"
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
        case .connected: Image(systemName: "lock.shield.fill")
        case .connecting, .disconnecting: Image(systemName: "shield.lefthalf.filled")
        case .disconnected: Image(systemName: "shield")
        }
    }
}
