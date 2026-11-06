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
                // Passage is menu-bar-only, which hides it from the Dock and Cmd-Tab.
                // Act like a normal app while Settings is open so the window can be found.
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 820, height: 620)
    }
}
