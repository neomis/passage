import SwiftUI

/// Holds the profile being edited, so changes can be saved or reverted.
@MainActor
final class ProfileEditor: ObservableObject {
    @Published var selectedID: String? {
        didSet { if selectedID != oldValue { load() } }
    }
    @Published var draft = Profile()
    @Published var password = ""
    @Published var psk = ""
    @Published var tab = "general"
    @Published private(set) var original = Profile()
    // Saved secrets live with the helper and are never read back. The fields stay
    // empty and only replace a secret when you type one.
    @Published private(set) var saved = Secrets.Saved()
    @Published var saveMessage = ""

    weak var store: ProfileStore?

    var isDirty: Bool { draft != original || !password.isEmpty || !psk.isEmpty }

    /// Saved secrets only apply to the gateway (and username) they were saved with.
    var passwordPrompt: String {
        if draft.gateway != original.gateway || draft.username != original.username, saved.password {
            return "Enter again: gateway or username changed"
        }
        return saved.password ? "Saved – type to replace" : "Required"
    }
    var pskPrompt: String {
        if draft.gateway != original.gateway, saved.psk { return "Enter again: gateway changed" }
        return saved.psk ? "Saved – type to replace" : "Required"
    }

    func load() {
        guard let id = selectedID, let p = store?.profile(id) else { return }
        draft = p; original = p
        password = ""; psk = ""
        saved = Secrets.status(p)
        saveMessage = ""
    }

    func save() {
        guard let store else { return }
        store.update(draft)
        var message = "Saved"
        // Always tell the helper, so it drops secrets that no longer match a changed
        // gateway or username.
        let typedSecret = !password.isEmpty || !psk.isEmpty
        let hasTarget = !draft.gateway.isEmpty && !draft.username.isEmpty
        if hasTarget || typedSecret {
            do {
                try Secrets.save(draft, password: draft.askPasswordEachTime ? nil : password, psk: psk,
                                 forgetPassword: draft.askPasswordEachTime)
            } catch let e as Secrets.Failure {
                message = "Saved, but the password or key wasn't: \(e.message)"
            } catch {}
        }
        load()
        saveMessage = message
    }
}

struct SettingsView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var vpn: VPNController
    @StateObject private var editor = ProfileEditor()

    var body: some View {
        NavigationSplitView {
            List(selection: $editor.selectedID) {
                ForEach(store.profiles) { p in
                    HStack {
                        LampSymbol(look: vpn.connectedID == p.id ? .lit : .off, size: 18)
                            .foregroundStyle(.secondary)
                        Text(p.name)
                    }
                    .tag(Optional(p.id))
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .toolbar(removing: .sidebarToggle)   // the connection list is always needed
            .safeAreaInset(edge: .bottom) { listButtons }
        } detail: {
            if editor.selectedID != nil, store.profile(editor.selectedID ?? "") != nil {
                ProfileForm(editor: editor, vpn: vpn)
            } else {
                Text(store.profiles.isEmpty ? "Click + to add a VPN connection" : "Select a connection")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            editor.store = store
            if editor.selectedID == nil { editor.selectedID = store.selectedID.isEmpty ? store.profiles.first?.id : store.selectedID }
        }
    }

    private var listButtons: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 2) {
                Button { editor.selectedID = store.add().id } label: { Image(systemName: "plus") }
                Button {
                    if let id = editor.selectedID { editor.selectedID = store.duplicate(id)?.id }
                } label: { Image(systemName: "plus.square.on.square") }
                    .disabled(editor.selectedID == nil)
                    .help("Duplicate")
                Button {
                    if let id = editor.selectedID, vpn.connectedID != id {
                        store.delete(id)
                        editor.selectedID = store.profiles.first?.id
                    }
                } label: { Image(systemName: "minus") }
                    .disabled(editor.selectedID == nil || vpn.connectedID == editor.selectedID)
                Spacer()
                helperStatus
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
        .background(.bar)
    }

    private var helperStatus: some View {
        Menu {
            switch vpn.helper {
            case .ready: Button("Reinstall Helper…") { vpn.installHelper() }
            case .outdated: Button("Update Helper…") { vpn.installHelper() }
            default: Button("Install Helper…") { vpn.installHelper() }
            }
            Button("Remove Helper…") { vpn.uninstallHelper() }
        } label: {
            Image(systemName: vpn.helper == .ready ? "checkmark.seal" : "exclamationmark.triangle")
                .foregroundStyle(vpn.helper == .ready ? .green : .orange)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help(vpn.helper == .ready ? "Helper installed" : "Helper not installed")
    }
}

// MARK: - Editor

struct ProfileForm: View {
    @ObservedObject var editor: ProfileEditor
    @ObservedObject var vpn: VPNController

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $editor.tab) {
                GeneralTab(editor: editor).tabItem { Text("General") }.tag("general")
                IPsecTab(editor: editor).tabItem { Text("IPsec") }.tag("ipsec")
                PPPTab(editor: editor).tabItem { Text("PPP") }.tag("ppp")
                IPv4Tab(editor: editor).tabItem { Text("IPv4") }.tag("ipv4")
            }
            .padding([.horizontal, .top])

            Divider()
            HStack {
                if let problem = editor.draft.problems.first {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.callout).lineLimit(2)
                } else if !editor.saveMessage.isEmpty && !editor.isDirty {
                    let ok = editor.saveMessage == "Saved"
                    Label(editor.saveMessage, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(ok ? .green : .orange).font(.callout).lineLimit(2)
                }
                Spacer()
                if vpn.connectedID == editor.draft.id && editor.isDirty {
                    Text("Reconnect to apply").font(.callout).foregroundStyle(.secondary)
                }
                Button("Revert") { editor.load() }.disabled(!editor.isDirty)
                Button("Save") { editor.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!editor.isDirty)
            }
            .padding()
        }
    }
}

private struct GeneralTab: View {
    @ObservedObject var editor: ProfileEditor
    var body: some View {
        Form {
            Section {
                TextField("Name", text: $editor.draft.name)
                TextField("Gateway", text: $editor.draft.gateway, prompt: Text("vpn.example.com"))
            }
            Section("User authentication") {
                TextField("Username", text: $editor.draft.username)
                Toggle("Ask for password every time", isOn: $editor.draft.askPasswordEachTime)
                if !editor.draft.askPasswordEachTime {
                    SecureField("Password", text: $editor.password,
                                prompt: Text(editor.passwordPrompt))
                }
                TextField("NT domain", text: $editor.draft.ntDomain, prompt: Text("Optional"))
            }
            Section {
                Button("Apply Cisco Meraki preset") { editor.draft.applyMerakiPreset() }
            } footer: {
                Text("Sets the IPsec and PPP options that Meraki Client VPN expects. You still need the gateway, username, password and pre-shared key.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct IPsecTab: View {
    @ObservedObject var editor: ProfileEditor
    var body: some View {
        Form {
            Section {
                Toggle("Enable IPsec tunnel to L2TP host", isOn: $editor.draft.ipsecEnabled)
            }
            if editor.draft.ipsecEnabled {
                Section("Machine authentication") {
                    LabeledContent("Type") { Text("Pre-shared key") }
                    SecureField("Pre-shared key", text: $editor.psk,
                                prompt: Text(editor.pskPrompt))
                    TextField("Remote ID", text: $editor.draft.remoteID, prompt: Text("Optional, e.g. the gateway's IP or FQDN"))
                    TextField("Local ID", text: $editor.draft.localID, prompt: Text("Optional"))
                }
                Section {
                    TextField("Phase 1 algorithms", text: $editor.draft.phase1Algorithms, prompt: Text("Default"))
                    TextField("Phase 2 algorithms", text: $editor.draft.phase2Algorithms, prompt: Text("Default"))
                    TextField("Phase 1 lifetime (minutes)", value: $editor.draft.phase1LifetimeMinutes, format: .number)
                    TextField("Phase 2 lifetime (minutes)", value: $editor.draft.phase2LifetimeMinutes, format: .number)
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Algorithms use strongSwan/NetworkManager format, e.g. aes128-sha1-modp2048 (phase 1) and aes128-sha1 (phase 2). Separate several with commas. Leave empty for strongSwan's defaults.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Add legacy proposals (3DES, SHA1, DH group 2)", isOn: $editor.draft.legacyProposals)
                    Toggle("Enforce UDP encapsulation", isOn: $editor.draft.forceUDPEncapsulation)
                    Toggle("Use IP compression", isOn: $editor.draft.ipCompression)
                    Toggle("Disable PFS", isOn: $editor.draft.disablePFS)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PPPTab: View {
    @ObservedObject var editor: ProfileEditor
    var body: some View {
        Form {
            Section("Allowed authentication methods") {
                Toggle("PAP", isOn: $editor.draft.allowPAP)
                Toggle("CHAP", isOn: $editor.draft.allowCHAP)
                Toggle("MSCHAP", isOn: $editor.draft.allowMSCHAP)
                Toggle("MSCHAPv2", isOn: $editor.draft.allowMSCHAPv2)
                Toggle("EAP", isOn: $editor.draft.allowEAP)
            }
            Section("Security and compression") {
                Toggle("Use Point-to-Point encryption (MPPE)", isOn: $editor.draft.useMPPE)
                if editor.draft.useMPPE {
                    Toggle("Require 128-bit encryption", isOn: $editor.draft.mppe128Only)
                    Toggle("Allow stateful encryption", isOn: $editor.draft.mppeStateful)
                }
                Toggle("Allow BSD data compression", isOn: $editor.draft.bsdCompression)
                Toggle("Allow Deflate data compression", isOn: $editor.draft.deflateCompression)
                Toggle("Use TCP header compression", isOn: $editor.draft.tcpHeaderCompression)
                Toggle("Use protocol field compression negotiation", isOn: $editor.draft.protocolFieldCompression)
                Toggle("Use Address/Control compression", isOn: $editor.draft.addressControlCompression)
            }
            Section("Echo") {
                Toggle("Send PPP echo packets", isOn: $editor.draft.sendEchoPackets)
            }
            Section("Misc") {
                TextField("MTU", value: $editor.draft.mtu, format: .number.grouping(.never))
                TextField("MRU", value: $editor.draft.mru, format: .number.grouping(.never))
            }
        }
        .formStyle(.grouped)
    }
}

private struct IPv4Tab: View {
    @ObservedObject var editor: ProfileEditor
    var body: some View {
        Form {
            Section {
                Toggle("Send all traffic through the VPN", isOn: $editor.draft.sendAllTraffic)
                TextField("Routes", text: $editor.draft.routes, prompt: Text("e.g. 10.0.0.0/8, 192.168.50.0/24"))
            } header: {
                Text("Routing")
            } footer: {
                Text(editor.draft.sendAllTraffic
                     ? "All traffic goes through the VPN. Extra routes are optional."
                     : "Only traffic for these networks goes through the VPN (split tunnel).")
                    .foregroundStyle(.secondary)
            }
            Section("DNS") {
                Toggle("Ignore DNS servers from the VPN", isOn: $editor.draft.ignoreAutomaticDNS)
                TextField("DNS servers", text: $editor.draft.dnsServers, prompt: Text("Optional, e.g. 10.0.0.53"))
                TextField("Search domains", text: $editor.draft.searchDomains, prompt: Text("Optional, e.g. corp.example.com"))
            }
        }
        .formStyle(.grouped)
    }
}
