import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var gateway: GatewayController

    var body: some View {
        Form {
            Section("Gateway") {
                LabeledContent("Status") {
                    Text(statusLabel)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Binary") {
                    Text(gateway.binaryPath ?? "not found")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Config") {
                    Text(gateway.configPath())
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                if let url = gateway.pageURL {
                    LabeledContent("WebUI") {
                        Link(url.absoluteString, destination: url)
                    }
                }
                Toggle("Prefer bundled wally binary", isOn: $gateway.preferBundledBinary)
                Button("Restart Gateway") {
                    Task { await gateway.restart() }
                }
            }

            Section("About") {
                LabeledContent("App") {
                    Text("Wally for macOS")
                }
                LabeledContent("Bundle ID") {
                    Text(Bundle.main.bundleIdentifier ?? "ai.wally.app")
                        .foregroundStyle(.secondary)
                }
                Link("GitHub repository", destination: URL(string: "https://github.com/yedamao/wally")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 360)
    }

    private var statusLabel: String {
        switch gateway.phase {
        case .idle: return "Idle"
        case .locatingBinary: return "Locating binary…"
        case .starting: return "Starting…"
        case .ready: return "Ready"
        case .failed: return "Failed"
        }
    }
}
