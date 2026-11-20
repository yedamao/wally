import Foundation
import os

protocol GatewayControllerDelegate: AnyObject {
    func gatewayControllerDidUpdate(_ controller: GatewayController)
}

/// Manages the local `wally webui` process and discovers the WebUI URL.
/// All delegate callbacks are delivered on the main queue.
final class GatewayController {
    enum Phase: Equatable {
        case idle
        case locatingBinary
        case starting
        case ready
        case failed(String)
    }

    weak var delegate: GatewayControllerDelegate?

    private(set) var phase: Phase = .idle
    private(set) var pageURL: URL?
    private(set) var binaryPath: String?
    private(set) var logTail: String = ""
    var preferBundledBinary = true

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var readinessWorkItem: DispatchWorkItem?
    private let log = Logger(subsystem: "ai.wally.app", category: "gateway")
    private var terminateObserver: NSObjectProtocol?
    private let stateQueue = DispatchQueue(label: "ai.wally.app.gateway")

    private let defaultHost = "127.0.0.1"
    private let defaultPort = 18790
    private let readyTimeout: TimeInterval = 45

    init() {
        terminateObserver = NotificationCenter.default.addObserver(
            forName: .wallyWillTerminate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
    }

    deinit {
        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
        }
        // Terminate without touching MainActor / delegate.
        killProcess()
    }

    func start() {
        stateQueue.async { [weak self] in
            self?.startLocked()
        }
    }

    func restart() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.stopLocked()
            Thread.sleep(forTimeInterval: 0.4)
            self.startLocked()
        }
    }

    func stop() {
        stateQueue.async { [weak self] in
            self?.stopLocked()
        }
    }

    // MARK: - Binary resolution

    func resolveBinary() -> String? {
        var candidates: [String] = []

        if preferBundledBinary {
            if let bundled = Bundle.main.path(forResource: "wally", ofType: nil) {
                candidates.append(bundled)
            }
            if let res = Bundle.main.resourceURL {
                candidates.append(res.appendingPathComponent("wally").path)
                candidates.append(res.appendingPathComponent("bin/wally").path)
            }
        }

        if let env = ProcessInfo.processInfo.environment["WALLY_BINARY"], !env.isEmpty {
            candidates.insert(env, at: 0)
        }

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

    func configPath() -> String {
        if let env = ProcessInfo.processInfo.environment["NANOBOT_GO_CONFIG"], !env.isEmpty {
            return (env as NSString).expandingTildeInPath
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.nanobot-go/config.json"
    }

    // MARK: - Private

    private func startLocked() {
        guard phase != .starting, phase != .ready else { return }
        setPhase(.locatingBinary, url: nil, clearLog: true)

        guard let binary = resolveBinary() else {
            setPhase(
                .failed(
                    "Could not find the wally binary.\n\n" +
                        "Build it with `go build -o bin/wally ./cmd/wally`, then either:\n" +
                        "• put it on your PATH, or\n" +
                        "• package the app with scripts/build-app.sh so it is bundled under Contents/Resources/wally."
                ),
                url: nil
            )
            return
        }
        binaryPath = binary
        notify()
        setPhase(.starting, url: nil)

        do {
            try launchWebUI(binary: binary)
        } catch {
            setPhase(.failed("Failed to start wally: \(error.localizedDescription)"), url: nil)
            return
        }

        waitUntilReady()
    }

    private func stopLocked() {
        readinessWorkItem?.cancel()
        readinessWorkItem = nil
        killProcess()
        if phase == .ready || phase == .starting {
            setPhase(.idle, url: nil)
        } else {
            pageURL = nil
            notify()
        }
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

    private func launchWebUI(binary: String) throws {
        killProcess()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = ["webui", "--yes", "--no-open"]
        proc.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        var env = ProcessInfo.processInfo.environment
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
            self?.stateQueue.async { self?.appendLog(text) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.stateQueue.async { self?.appendLog(text) }
        }

        proc.terminationHandler = { [weak self] process in
            self?.stateQueue.async {
                guard let self else { return }
                if self.process == process {
                    self.process = nil
                    if self.phase == .ready || self.phase == .starting {
                        let code = process.terminationStatus
                        self.setPhase(
                            .failed("wally webui exited (status \(code)).\n\n\(self.logTail)"),
                            url: nil
                        )
                    }
                }
            }
        }

        try proc.run()
        process = proc
        log.info("started \(binary, privacy: .public) webui pid=\(proc.processIdentifier)")
    }

    private func killProcess() {
        guard let proc = process else { return }
        process = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        if proc.isRunning {
            proc.terminate()
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
        notify()
    }

    private func waitUntilReady() {
        let port = resolvedPort()
        let host = resolvedHost()
        let base = URL(string: "http://\(host):\(port)")!
        let page = base.appendingPathComponent("ui/")
        let health = base.appendingPathComponent("healthz")
        let deadline = Date().addingTimeInterval(readyTimeout)

        let work = DispatchWorkItem { [weak self] in
            self?.pollReady(page: page, health: health, deadline: deadline)
        }
        readinessWorkItem = work
        stateQueue.async(execute: work)
    }

    private func pollReady(page: URL, health: URL, deadline: Date) {
        if readinessWorkItem?.isCancelled == true { return }
        if process?.isRunning != true {
            if phase == .starting {
                setPhase(
                    .failed(
                        "The WebUI process exited before becoming ready.\n\n" +
                            (logTail.isEmpty ? "No process output was captured." : logTail)
                    ),
                    url: nil
                )
            }
            return
        }
        if ping(health), ping(page) {
            setPhase(.ready, url: page)
            return
        }
        if Date() >= deadline {
            let port = resolvedPort()
            setPhase(
                .failed(
                    "The WebUI did not become ready in time.\n\n" +
                        "Check that nothing else is using port \(port), " +
                        "and that ~/.nanobot-go/config.json is valid.\n\n" +
                        (logTail.isEmpty ? "No process output was captured." : logTail)
                ),
                url: nil
            )
            killProcess()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.pollReady(page: page, health: health, deadline: deadline)
        }
        readinessWorkItem = work
        stateQueue.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func ping(_ url: URL) -> Bool {
        var req = URLRequest(url: url, timeoutInterval: 1.5)
        req.httpMethod = "GET"
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        let task = URLSession.shared.dataTask(with: req) { _, resp, _ in
            if let http = resp as? HTTPURLResponse {
                ok = (200..<400).contains(http.statusCode)
            }
            sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 2)
        return ok
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

    private func setPhase(_ phase: Phase, url: URL?, clearLog: Bool = false) {
        self.phase = phase
        self.pageURL = url
        if clearLog { logTail = "" }
        notify()
    }

    private func notify() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.gatewayControllerDidUpdate(self)
        }
    }
}
