import XCTest

/// Pure helpers mirrored from GatewayController for unit tests without
/// spinning up AppKit. Keep these in sync with resolvedHost/port logic.
enum GatewayURLHelpers {
    static let defaultHost = "127.0.0.1"
    static let defaultPort = 18790

    static func browserHost(_ host: String?) -> String {
        let trimmed = host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return defaultHost }
        if trimmed == "0.0.0.0" || trimmed == "::" || trimmed == "[::]" {
            return defaultHost
        }
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    static func browserPort(_ port: Int?) -> Int {
        guard let port, port > 0 else { return defaultPort }
        return port
    }

    static func pageURL(host: String?, port: Int?) -> URL {
        URL(string: "http://\(browserHost(host)):\(browserPort(port))/ui/")!
    }
}

final class GatewayConfigTests: XCTestCase {
    func testDefaultPageURL() {
        XCTAssertEqual(
            GatewayURLHelpers.pageURL(host: nil, port: nil).absoluteString,
            "http://127.0.0.1:18790/ui/"
        )
    }

    func testWildcardHostBecomesLoopback() {
        XCTAssertEqual(GatewayURLHelpers.browserHost("0.0.0.0"), "127.0.0.1")
        XCTAssertEqual(GatewayURLHelpers.browserHost("::"), "127.0.0.1")
    }

    func testCustomPort() {
        XCTAssertEqual(
            GatewayURLHelpers.pageURL(host: "127.0.0.1", port: 19000).absoluteString,
            "http://127.0.0.1:19000/ui/"
        )
    }

    func testZeroPortFallsBack() {
        XCTAssertEqual(GatewayURLHelpers.browserPort(0), 18790)
        XCTAssertEqual(GatewayURLHelpers.browserPort(-1), 18790)
    }
}
