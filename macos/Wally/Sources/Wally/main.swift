import AppKit

// NSApplication.delegate is weak; keep a process-lifetime retain.
private var retainedDelegate: AppDelegate?

autoreleasepool {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    retainedDelegate = delegate
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
