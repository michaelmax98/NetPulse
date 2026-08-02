import SwiftUI

enum DefaultsKey {
    static let glyphMode = "glyphMode"
    static let useBits = "useBits"
    static let historyWindow = "historyWindow"
    static let showSessionSection = "showSessionSection"
    static let showInterfacesSection = "showInterfacesSection"
    static let showSettingsSection = "showSettingsSection"
}

@main
struct NetPulseApp: App {
    @StateObject private var monitor = NetMonitor()

    var body: some Scene {
        MenuBarExtra {
            PanelView(monitor: monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
