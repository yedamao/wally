import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var gateway: GatewayController
    @State private var reloadToken = 0
    @State private var showLog = false

    var body: some View {
        ZStack {
            switch gateway.phase {
            case .ready:
                if let url = gateway.pageURL {
                    WebView(url: url, reloadToken: $reloadToken)
                        .ignoresSafeArea()
                }
            case .idle, .locatingBinary, .starting:
                LaunchScreen(phase: gateway.phase)
            case .failed(let message):
                FailureView(message: message, log: gateway.logTail) {
                    Task { await gateway.restart() }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await gateway.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wallyReload)) { _ in
            reloadToken += 1
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if gateway.phase == .ready {
                    Button {
                        reloadToken += 1
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .help("Reload WebUI")
                }

                Button {
                    showLog.toggle()
                } label: {
                    Label("Logs", systemImage: "text.alignleft")
                }
                .help("Show gateway output")

                Button {
                    Task { await gateway.restart() }
                } label: {
                    Label("Restart", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Restart gateway")
            }
        }
        .sheet(isPresented: $showLog) {
            LogSheet(text: gateway.logTail, binary: gateway.binaryPath, config: gateway.configPath())
        }
    }
}

struct LaunchScreen: View {
    let phase: GatewayController.Phase

    var body: some View {
        VStack(spacing: 20) {
            BrandMark()
                .frame(width: 88, height: 88)

            Text("Wally")
                .font(.system(size: 34, weight: .semibold, design: .rounded))

            Text(statusText)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ProgressView()
                .controlSize(.small)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var statusText: String {
        switch phase {
        case .locatingBinary:
            return "Looking for the wally binary…"
        case .starting:
            return "Starting the local gateway and WebUI…"
        default:
            return "Preparing…"
        }
    }
}

struct FailureView: View {
    let message: String
    let log: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            BrandMark()
                .frame(width: 72, height: 72)
                .opacity(0.85)

            Text("Couldn’t open Wally")
                .font(.system(size: 22, weight: .semibold, design: .rounded))

            Text(message)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: 560)
                .multilineTextAlignment(.leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))

            if !log.isEmpty {
                ScrollView {
                    Text(log)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: 560, maxHeight: 140)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }

            HStack(spacing: 12) {
                Button("Try Again", action: onRetry)
                    .keyboardShortcut(.defaultAction)
                Button("Open Config Folder") {
                    let home = FileManager.default.homeDirectoryForCurrentUser
                    NSWorkspace.shared.open(home.appendingPathComponent(".nanobot-go"))
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct LogSheet: View {
    let text: String
    let binary: String?
    let config: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Gateway")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Group {
                Text("Binary: \(binary ?? "—")")
                Text("Config: \(config)")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

            ScrollView {
                Text(text.isEmpty ? "(no output yet)" : text)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        }
        .padding(20)
        .frame(width: 640, height: 420)
    }
}

struct BrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.95, green: 0.65, blue: 0.35))
            // Simplified Wally face from the WebUI favicon.
            VStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(red: 0.07, green: 0.20, blue: 0.23))
                Capsule()
                    .fill(Color(red: 0.07, green: 0.20, blue: 0.23))
                    .frame(width: 54, height: 36)
                    .overlay {
                        HStack(spacing: 10) {
                            Circle().fill(.white).frame(width: 8, height: 8)
                            Circle().fill(.white).frame(width: 8, height: 8)
                        }
                    }
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }
}
