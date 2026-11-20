import Foundation
import os

/// Manages the local `wally webui` process and discovers the WebUI URL.
@MainActor
final class GatewayController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case locatingBinary
        case starting
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var pageURL: URL?
    @Published private(set) var binaryPath: String?
    @Published private(set) var logTail: String = ""
    @Published var preferBundledBinary = true

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var readinessTask: Task<Void, Never>?
    private let log = Logger(subsystem: "ai.wally.app", category: "gateway")
    private var terminateObserver: NSObjectProtocol?

    private let defaultHost = "127.0.0.1"
    private let defaultPort = 18790
    private let readyTimeout: TimeInterval = 45

    init() {
        terminateObserver = NotificationCenter.default.addObserver(
            forName: .wallyWillTerminate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
        }
    }

    deinit {
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
        stopSync()
    }

    func start() async {
        guard phase != .starting, phase != .ready else { return }
        phase = .locatingBinary
        pageURL = nil
        logTail = ""

        guard let binary = resolveBinary() else {
            phase = .failed(
                "Could not find the wally binary.\n\n" +
                    "Build it with `go build -o bin/wally ./cmd/wally`, then either:\n" +
                    "• put it on your PATH, or\n" +
                    "• package the app with scripts/build-app.sh so it is bundled under Contents/Resources/wally."
            )
            return
        }
        binaryPath = binary
        phase = .starting

        do {
            try launchWebUI(binary: binary)
        } catch {
            phase = .failed("Failed to start wally: \(error.localizedDescription)")
            return
        }

        let url = await waitUntilReady()
        if let url {
            pageURL = url
            phase = .ready
        } else if phase == .starting {
            phase = .failed(
                "The WebUI did not become ready in time.\n\n" +
                    "Check that nothing else is using port \(resolvedPort()), " +
                    "and that ~/.nanobot-go/config.json is valid.\n\n" +
                    (logTail.isEmpty ? "No process output was captured." : logTail)
            )
            stop()
        }
    }

    func restart() async {
        stop()
        // Brief pause so the previous lease can release the port.
        try? await Task.sleep(nanoseconds: 400_000_000)
        await start()
    }

    func stop() {
        readinessTask?.cancel()
        readinessTask = nil
        stopSync()
        if phase == .ready || phase == .starting {
            phase = .idle
        }
        pageURL = nil
    }

    // MARK: - Binary resolution

    func resolveBinary() -> String? {
        var candidates: [String] = []

        if preferBundledBinary {
            if let bundled = Bundle.main.path(forResource: "wally", ofType: nil) {
                candidates.append(bundled)
            }
            // SPM resource layout / ad-hoc .app packaging
            if let res = Bundle.main.resourceURL {
                candidates.append(res.appendingPathComponent("wally").path)
                candidates.append(res.appendingPathComponent("bin/wally").path)
            }
        }

        if let env = ProcessInfo.processInfo.environment["WALLY_BINARY"], !env.isEmpty {
            candidates.insert(env, at: 0)
        }

        // Common local build locations relative to the app / cwd
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        candidates.append(contentsOf: [
            "\(home)/go/bin/wally",
            "\(home)/go/bin/nanobot",
            "/opt/homebrew/bin/wally",
            "/usr/local/bin/wally",
        ])

        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                candidates.append("\(dir)/wally")
                candidates.append("\(dir)/nanobot")
            }
        }

        let fm = FileManager.default
        for path in candidates {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue,
               fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return which("wally") ?? which("nanobot")
    }

    private func which(_ name: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [name]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty else { return nil }
        return path
    }

    // MARK: - Process

    private func launchWebUI(binary: String) throws {
        stopSync()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = ["webui", "--yes", "--no-open"]
        proc.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        var env = ProcessInfo.processInfo.environment
        // Prefer the real binary name in child logs / service installs.
        env["NANOBOT_GO_CLI_NAME"] = "wally"
        proc.environment = env

        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        stdoutPipe = out
        stderrPipe = err

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendLog(text)
            }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendLog(text)
            }
        }

        proc.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self else { return }
                if self.process == process {
                    self.process = nil
                    if self.phase == .ready || self.phase == .starting {
                        let code = process.terminationStatus
                        self.phase = .failed("wally webui exited (status \(code)).\n\n\(self.logTail)")
                        self.pageURL = nil
                    }
                }
            }
        }

        try proc.run()
        process = proc
        log.info("started \(binary, privacy: .public) webui pid=\(proc.processIdentifier)")
    }

    private func stopSync() {
        guard let proc = process else { return }
        process = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        if proc.isRunning {
            proc.terminate()
            // Give it a moment for the lease release; escalate if needed.
            let deadline = Date().addingTimeInterval(3)
            while proc.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if proc.isRunning {
                proc.interrupt()
            }
        }
    }

    private func appendLog(_ text: String) {
        logTail = String((logTail + text).suffix(4000))
    }

    // MARK: - Readiness

    private func waitUntilReady() async -> URL? {
        let port = resolvedPort()
        let host = resolvedHost()
        let base = URL(string: "http://\(host):\(port)")!
        let page = base.appendingPathComponent("ui/")
        let health = base.appendingPathComponent("healthz")

        let deadline = Date().addingTimeInterval(readyTimeout)
        while Date() < deadline {
            if Task.isCancelled { return nil }
            if process?.isRunning != true {
                return nil
            }
            if await ping(health), await ping(page) {
                return page
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return nil
    }

    private func ping(_ url: URL) async -> Bool {
        var req = URLRequest(url: url, timeoutInterval: 1.5)
        req.httpMethod = "GET"
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            return (200..<400).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private func resolvedPort() -> Int {
        if let port = readGatewayConfig()?.port, port > 0 {
            return port
        }
        return defaultPort
    }

    private func resolvedHost() -> String {
        let host = readGatewayConfig()?.host?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host, !host.isEmpty {
            // WKWebView should use a loopback literal when the gateway
            // binds 0.0.0.0 / :: .
            if host == "0.0.0.0" || host == "::" || host == "[::]" {
                return defaultHost
            }
            return host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
        return defaultHost
    }

    private struct GatewayJSON: Decodable {
        var host: String?
        var port: Int?
    }

    private struct ConfigJSON: Decodable {
        var gateway: GatewayJSON?
    }

    private func readGatewayConfig() -> GatewayJSON? {
        let path = configPath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? JSONDecoder().decode(ConfigJSON.self, from: data).gateway
    }

    func configPath() -> String {
        if let env = ProcessInfo.processInfo.environment["NANOBOT_GO_CONFIG"], !env.isEmpty {
            return (env as NSString).expandingTildeInPath
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.nanobot-go/config.json"
    }
}
