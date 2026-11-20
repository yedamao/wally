import AppKit
import WebKit

enum AppTheme: String {
    case light
    case dark

    var appearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// WebUI --bg-1 (sidebar / topbar), used for native chrome fill.
    var chromeColor: NSColor {
        switch self {
        case .light:
            return NSColor(calibratedRed: 250 / 255, green: 250 / 255, blue: 250 / 255, alpha: 1) // #fafafa
        case .dark:
            return NSColor(calibratedRed: 12 / 255, green: 12 / 255, blue: 14 / 255, alpha: 1) // #0c0c0e
        }
    }

    var canvasColor: NSColor {
        switch self {
        case .light:
            return NSColor(calibratedRed: 244 / 255, green: 244 / 255, blue: 245 / 255, alpha: 1) // #f4f4f5
        case .dark:
            return NSColor(calibratedRed: 9 / 255, green: 9 / 255, blue: 11 / 255, alpha: 1) // #09090b
        }
    }

    static func fromMessage(_ body: Any) -> AppTheme? {
        if let s = body as? String {
            return AppTheme(rawValue: s.lowercased())
        }
        if let dict = body as? [String: Any], let s = dict["theme"] as? String {
            return AppTheme(rawValue: s.lowercased())
        }
        return nil
    }

    static var system: AppTheme {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? .dark : .light
    }
}

protocol ThemeBridgeDelegate: AnyObject {
    func themeBridgeDidResolve(_ theme: AppTheme)
}

/// Receives theme updates from the WebUI (data-theme) via WKScriptMessageHandler.
final class ThemeBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "wallyTheme"

    weak var delegate: ThemeBridgeDelegate?

    /// Injected into the page: watch data-theme and post light/dark to native.
    static var userScript: WKUserScript {
        let source = """
        (function () {
          if (window.__wallyThemeBridge) return;
          window.__wallyThemeBridge = true;
          function resolved() {
            var t = document.documentElement.getAttribute("data-theme");
            if (t === "light" || t === "dark") return t;
            try {
              var pref = localStorage.getItem("nanobot.theme");
              if (pref === "light" || pref === "dark") return pref;
            } catch (e) {}
            return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
          }
          function post() {
            try {
              var theme = resolved();
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.wallyTheme) {
                window.webkit.messageHandlers.wallyTheme.postMessage(theme);
              }
            } catch (e) {}
          }
          post();
          try {
            new MutationObserver(post).observe(document.documentElement, {
              attributes: true,
              attributeFilter: ["data-theme"]
            });
          } catch (e) {}
          try {
            window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", post);
          } catch (e) {}
          document.addEventListener("visibilitychange", function () {
            if (!document.hidden) post();
          });
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.handlerName, let theme = AppTheme.fromMessage(message.body) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.themeBridgeDidResolve(theme)
        }
    }
}
