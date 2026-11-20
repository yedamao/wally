import AppKit
import WebKit

final class MainWindowController: NSWindowController, GatewayControllerDelegate, NSWindowDelegate {
    private let gateway: GatewayController
    private let split = NSView()
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

    /// Matches WebUI --bg-1 so the transparent title bar blends with the sidebar.
    private let chromeColor = NSColor(calibratedRed: 12 / 255, green: 12 / 255, blue: 14 / 255, alpha: 1)

    init(gateway: GatewayController) {
        self.gateway = gateway
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Wally"
        window.minSize = NSSize(width: 960, height: 640)
        window.center()
        // Transparent title bar (no separator band). The WebView is pinned
        // to contentLayoutGuide so it clears the traffic lights — CSS
        // injection cannot pad the page because the WebUI CSP blocks it.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.backgroundColor = chromeColor
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = buildContent(in: window)
        gateway.delegate = self
        installObservers()
        render(gateway)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        for obs in [reloadObserver, openObserver, restartObserver, logsObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func gatewayControllerDidUpdate(_ controller: GatewayController) {
        render(controller)
    }

    private func buildContent(in window: NSWindow) -> NSView {
        split.wantsLayer = true
        split.layer?.backgroundColor = chromeColor.cgColor
        webContainer.translatesAutoresizingMaskIntoConstraints = false
        overlay.translatesAutoresizingMaskIntoConstraints = false
        split.addSubview(webContainer)
        split.addSubview(overlay)

        // Pin below the title bar / traffic lights. The strip above stays
        // chromeColor and remains system-draggable.
        // contentLayoutGuide is typed as Any? on NSWindow; cast to NSLayoutGuide.
        let topAnchor: NSLayoutYAxisAnchor
        if let guide = window.contentLayoutGuide as? NSLayoutGuide {
            topAnchor = guide.topAnchor
        } else {
            topAnchor = split.safeAreaLayoutGuide.topAnchor
        }
        NSLayoutConstraint.activate([
            webContainer.leadingAnchor.constraint(equalTo: split.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: split.trailingAnchor),
            webContainer.topAnchor.constraint(equalTo: topAnchor),
            webContainer.bottomAnchor.constraint(equalTo: split.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: split.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: split.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: split.bottomAnchor),
        ])
        return split
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
        }
        if !didConfigureToolbar {
            window?.toolbar = makeToolbar()
            didConfigureToolbar = true
        }
    }

    private func ensureWebView() {
        if webView != nil { return }
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.setValue(false, forKey: "drawsBackground")
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
            (gateway.logTail.isEmpty ? "(no output yet)" : gateway.logTail)
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
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
