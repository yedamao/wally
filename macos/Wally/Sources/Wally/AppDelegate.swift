import AppKit

extension Notification.Name {
    static let wallyReload = Notification.Name("ai.wally.app.reload")
    static let wallyWillTerminate = Notification.Name("ai.wally.app.willTerminate")
    static let wallyOpenInBrowser = Notification.Name("ai.wally.app.openInBrowser")
    static let wallyRestartGateway = Notification.Name("ai.wally.app.restartGateway")
    static let wallyShowLogs = Notification.Name("ai.wally.app.showLogs")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController?
    private let gateway = GatewayController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = buildMenu()

        let window = MainWindowController(gateway: gateway)
        mainWindow = window
        window.showWindow(nil)
        window.present()

        gateway.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        mainWindow?.present()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.post(name: .wallyWillTerminate, object: nil)
        gateway.stop()
    }

    private func buildMenu() -> NSMenu {
        let main = NSMenu()

        let appMenuItem = NSMenuItem()
        main.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Wally", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Wally", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Wally", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenuItem = NSMenuItem()
        main.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let viewMenuItem = NSMenuItem()
        main.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Reload WebUI", action: #selector(reloadWebUI(_:)), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Open in Browser", action: #selector(openInBrowser(_:)), keyEquivalent: "o").keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Show Logs", action: #selector(showLogs(_:)), keyEquivalent: "l")
        viewMenu.addItem(withTitle: "Restart Gateway", action: #selector(restartGateway(_:)), keyEquivalent: "r").keyEquivalentModifierMask = [.command, .shift]

        let windowMenuItem = NSMenuItem()
        main.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        let helpMenuItem = NSMenuItem()
        main.addItem(helpMenuItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        helpMenu.addItem(withTitle: "Wally Help", action: #selector(openHelp(_:)), keyEquivalent: "")
        NSApp.helpMenu = helpMenu

        return main
    }

    @objc private func reloadWebUI(_ sender: Any?) {
        NotificationCenter.default.post(name: .wallyReload, object: nil)
    }

    @objc private func openInBrowser(_ sender: Any?) {
        NotificationCenter.default.post(name: .wallyOpenInBrowser, object: nil)
    }

    @objc private func restartGateway(_ sender: Any?) {
        NotificationCenter.default.post(name: .wallyRestartGateway, object: nil)
    }

    @objc private func showLogs(_ sender: Any?) {
        NotificationCenter.default.post(name: .wallyShowLogs, object: nil)
    }

    @objc private func openHelp(_ sender: Any?) {
        if let url = URL(string: "https://github.com/yedamao/wally") {
            NSWorkspace.shared.open(url)
        }
    }
}
