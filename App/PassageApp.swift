import SwiftUI

@main
struct PassageApp: App {
    @StateObject private var store = ProfileStore()
    @StateObject private var vpn = VPNController()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(store: store, vpn: vpn)
        } label: {
            MenuBarIcon(vpn: vpn)
        }
        .menuBarExtraStyle(.window)

        Window("Passage Settings", id: "settings") {
            SettingsView(store: store, vpn: vpn)
        }
        .defaultSize(width: 820, height: 620)
    }
}
