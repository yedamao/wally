import AppKit
import SwiftUI

@main
struct WallyApp: App {
    @StateObject private var gateway = GatewayController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gateway)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .sidebar) {
                Button("Reload WebUI") {
                    NotificationCenter.default.post(name: .wallyReload, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Open in Browser") {
                    if let url = gateway.pageURL {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(gateway.pageURL == nil)

                Divider()

                Button("Restart Gateway") {
                    Task { await gateway.restart() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Wally Help") {
                    if let url = URL(string: "https://github.com/yedamao/wally") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(gateway)
        }
    }
}

extension Notification.Name {
    static let wallyReload = Notification.Name("ai.wally.app.reload")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // GatewayController tears down via deinit / onDisappear; also
        // stop here so quitting from the Dock kills the webui lease.
        NotificationCenter.default.post(name: .wallyWillTerminate, object: nil)
    }
}

extension Notification.Name {
    static let wallyWillTerminate = Notification.Name("ai.wally.app.willTerminate")
}
