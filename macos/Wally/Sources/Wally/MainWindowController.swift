import AppKit
import WebKit

final class MainWindowController: NSWindowController, GatewayControllerDelegate, NSWindowDelegate, ThemeBridgeDelegate {
    private let gateway: GatewayController
    private let themeBridge = ThemeBridge()
    private let root = NSView()
    private let overlay = StatusOverlayView()
    private let webContainer = NSView()
    private var webView: WKWebView?
    private var toolbar: NSToolbar?
    private var reloadObserver: NSObjectProtocol?
    private var openObserver: NSObjectProtocol?
    private var restartObserver: NSObjectProtocol?
    private var logsObserver: NSObjectProtocol?
    private var loadedURL: URL?
    private var didConfigureToolbar = false
    private var theme: AppTheme = .system

    init(gateway: GatewayController) {
        self.gateway = gateway
        // Plain titled window — reliable visibility. Transparent /
        // fullSizeContentView chrome caused invisible launches for some users.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Wally"
        window.minSize = NSSize(width: 960, height: 640)
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        themeBridge.delegate = self
        applyTheme(AppTheme.system)
        installContent(in: window)
        gateway.delegate = self
        installObservers()
        render(gateway)
        LaunchLog.write("MainWindowController init ok")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let controller = webView?.configuration.userContentController {
            controller.removeScriptMessageHandler(forName: ThemeBridge.handlerName)
        }
        for obs in [reloadObserver, openObserver, restartObserver, logsObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func themeBridgeDidResolve(_ theme: AppTheme) {
        applyTheme(theme)
    }

    private func applyTheme(_ theme: AppTheme) {
        self.theme = theme
        guard let window else { return }
        window.appearance = theme.appearance
        window.backgroundColor = theme.chromeColor
        root.layer?.backgroundColor = theme.chromeColor.cgColor
        webContainer.layer?.backgroundColor = theme.canvasColor.cgColor
        overlay.applyTheme(theme)
        LaunchLog.write("theme=\(theme.rawValue)")
    }

    func present() {
        guard let window else {
            LaunchLog.write("present: no window")
            return
        }
        if window.screen == nil {
            window.setFrameOrigin(NSPoint(x: 120, y: 120))
        } else {
            window.center()
        }
        window.setIsVisible(true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        LaunchLog.write("present: visible=\(window.isVisible) key=\(window.isKeyWindow) frame=\(window.frame)")
    }

    func gatewayControllerDidUpdate(_ controller: GatewayController) {
        render(controller)
    }

    private func installContent(in window: NSWindow) {
        guard let content = window.contentView else { return }

        root.wantsLayer = true
        root.layer?.backgroundColor = theme.chromeColor.cgColor
        webContainer.wantsLayer = true
        webContainer.layer?.backgroundColor = theme.canvasColor.cgColor
        root.translatesAutoresizingMaskIntoConstraints = false
        webContainer.translatesAutoresizingMaskIntoConstraints = false
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.applyTheme(theme)

        content.addSubview(root)
        root.addSubview(webContainer)
        root.addSubview(overlay)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            webContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webContainer.topAnchor.constraint(equalTo: root.topAnchor),
            webContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            overlay.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: root.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
    }

    private func installObservers() {
        let nc = NotificationCenter.default
        reloadObserver = nc.addObserver(forName: .wallyReload, object: nil, queue: .main) { [weak self] _ in
            self?.webView?.reload()
        }
        openObserver = nc.addObserver(forName: .wallyOpenInBrowser, object: nil, queue: .main) { [weak self] _ in
            if let url = self?.gateway.pageURL {
                NSWorkspace.shared.open(url)
            }
        }
        restartObserver = nc.addObserver(forName: .wallyRestartGateway, object: nil, queue: .main) { [weak self] _ in
            self?.gateway.restart()
        }
        logsObserver = nc.addObserver(forName: .wallyShowLogs, object: nil, queue: .main) { [weak self] _ in
            self?.showLogs()
        }
    }

    private func render(_ controller: GatewayController) {
        switch controller.phase {
        case .ready:
            overlay.isHidden = true
            if let url = controller.pageURL {
                ensureWebView()
                if loadedURL != url {
                    loadedURL = url
                    webView?.load(URLRequest(url: url))
                    LaunchLog.write("loading \(url.absoluteString)")
                }
            }
        case .idle, .locatingBinary, .starting:
            overlay.isHidden = false
            overlay.showLaunch(phase: controller.phase)
        case .failed(let message):
            overlay.isHidden = false
            overlay.showFailure(message: message, log: controller.logTail) { [weak self] in
                self?.gateway.restart()
            }
            LaunchLog.write("gateway failed: \(message.prefix(200))")
        }
        if !didConfigureToolbar {
            window?.toolbar = makeToolbar()
            didConfigureToolbar = true
        }
    }

    private func ensureWebView() {
        if webView != nil { return }
        let config = WKWebViewConfiguration()
        let uc = config.userContentController
        uc.add(themeBridge, name: ThemeBridge.handlerName)
        uc.addUserScript(ThemeBridge.userScript)
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.translatesAutoresizingMaskIntoConstraints = false
        webContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: webContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor),
        ])
        webView = view
    }

    private func makeToolbar() -> NSToolbar {
        if let toolbar { return toolbar }
        let toolbar = NSToolbar(identifier: "WallyToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        toolbar.delegate = self
        self.toolbar = toolbar
        return toolbar
    }

    private func showLogs() {
        let alert = NSAlert()
        alert.messageText = "Gateway"
        alert.informativeText =
            "Binary: \(gateway.binaryPath ?? "—")\nConfig: \(gateway.configPath())\n\n" +
            (gateway.logTail.isEmpty ? "(no output yet)" : gateway.logTail) +
            "\n\nLaunch log: \(LaunchLog.url.path)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Launch Log")
        if let window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertSecondButtonReturn {
                    NSWorkspace.shared.open(LaunchLog.url)
                }
            }
        } else {
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.open(LaunchLog.url)
            }
        }
    }
}

extension MainWindowController: NSToolbarDelegate {
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .wallyReload, .wallyLogs, .wallyRestart]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .wallyReload, .wallyLogs, .wallyRestart]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .wallyReload:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Reload"
            item.toolTip = "Reload WebUI"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")
            item.target = self
            item.action = #selector(toolbarReload)
            return item
        case .wallyLogs:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Logs"
            item.toolTip = "Show gateway output"
            item.image = NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Logs")
            item.target = self
            item.action = #selector(toolbarLogs)
            return item
        case .wallyRestart:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Restart"
            item.toolTip = "Restart gateway"
            item.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Restart")
            item.target = self
            item.action = #selector(toolbarRestart)
            return item
        default:
            return nil
        }
    }

    @objc private func toolbarReload() {
        webView?.reload()
    }

    @objc private func toolbarLogs() {
        showLogs()
    }

    @objc private func toolbarRestart() {
        gateway.restart()
    }
}

extension NSToolbarItem.Identifier {
    static let wallyReload = NSToolbarItem.Identifier("ai.wally.reload")
    static let wallyLogs = NSToolbarItem.Identifier("ai.wally.logs")
    static let wallyRestart = NSToolbarItem.Identifier("ai.wally.restart")
}

extension MainWindowController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Re-post theme after navigation in case the injected script raced.
        webView.evaluateJavaScript(
            "(function(){try{var t=document.documentElement.getAttribute('data-theme');if(t!=='light'&&t!=='dark'){t=window.matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light'}if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.wallyTheme){window.webkit.messageHandlers.wallyTheme.postMessage(t)}}catch(e){}})()"
        )
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if navigationAction.navigationType == .linkActivated,
           let host = url.host,
           !isLocalHost(host) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.begin { result in
            completionHandler(result == .OK ? panel.urls : nil)
        }
    }

    private func isLocalHost(_ host: String) -> Bool {
        host == "127.0.0.1" || host == "localhost" || host == "::1" || host.hasSuffix(".localhost")
    }
}
