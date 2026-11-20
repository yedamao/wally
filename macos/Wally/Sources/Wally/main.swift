import AppKit
import Foundation

enum LaunchLog {
    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Wally", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("launch.log")
    }()

    static func write(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
        fputs(line, stderr)
    }
}

LaunchLog.write("main: starting")

// NSApplication.delegate is weak; keep a process-lifetime retain.
private var retainedDelegate: AppDelegate?

autoreleasepool {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    retainedDelegate = delegate
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    LaunchLog.write("main: entering run loop")
    app.run()
    LaunchLog.write("main: run loop exited")
}
