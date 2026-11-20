import AppKit

/// Launch / error overlay shown while the WebUI is not ready.
final class StatusOverlayView: NSView {
    private let stack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "Wally")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private let retryButton = NSButton(title: "Try Again", target: nil, action: nil)
    private let configButton = NSButton(title: "Open Config Folder", target: nil, action: nil)
    private var onRetry: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        titleLabel.font = .systemFont(ofSize: 34, weight: .semibold)
        titleLabel.alignment = .center

        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.maximumNumberOfLines = 3

        detailLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .left
        detailLabel.maximumNumberOfLines = 20
        detailLabel.isHidden = true

        spinner.style = .spinning
        spinner.controlSize = .small

        retryButton.target = self
        retryButton.action = #selector(retryTapped)
        retryButton.keyEquivalent = "\r"
        retryButton.isHidden = true

        configButton.target = self
        configButton.action = #selector(openConfig)
        configButton.isHidden = true

        let buttons = NSStackView(views: [retryButton, configButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12
        buttons.distribution = .gravityAreas

        let brand = BrandMarkView(frame: .zero)
        brand.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            brand.widthAnchor.constraint(equalToConstant: 88),
            brand.heightAnchor.constraint(equalToConstant: 88),
        ])

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(brand)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(detailLabel)
        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(buttons)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40),
            detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showLaunch(phase: GatewayController.Phase) {
        retryButton.isHidden = true
        configButton.isHidden = true
        detailLabel.isHidden = true
        spinner.isHidden = false
        spinner.startAnimation(nil)
        switch phase {
        case .locatingBinary:
            statusLabel.stringValue = "Looking for the wally binary…"
        case .starting:
            statusLabel.stringValue = "Starting the local gateway and WebUI…"
        default:
            statusLabel.stringValue = "Preparing…"
        }
    }

    func showFailure(message: String, log: String, onRetry: @escaping () -> Void) {
        self.onRetry = onRetry
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        retryButton.isHidden = false
        configButton.isHidden = false
        statusLabel.stringValue = "Couldn’t open Wally"
        var detail = message
        if !log.isEmpty {
            detail += "\n\n" + log
        }
        detailLabel.stringValue = detail
        detailLabel.isHidden = false
    }

    @objc private func retryTapped() {
        onRetry?()
    }

    @objc private func openConfig() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        NSWorkspace.shared.open(home.appendingPathComponent(".nanobot-go"))
    }
}

final class BrandMarkView: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 88, height: 88) }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let bg = NSColor(calibratedRed: 0.95, green: 0.65, blue: 0.35, alpha: 1)
        let ink = NSColor(calibratedRed: 0.07, green: 0.20, blue: 0.23, alpha: 1)
        let path = NSBezierPath(roundedRect: bounds, xRadius: 22, yRadius: 22)
        bg.setFill()
        path.fill()

        let face = NSBezierPath(roundedRect: NSRect(x: 17, y: 18, width: 54, height: 36), xRadius: 14, yRadius: 14)
        ink.setFill()
        face.fill()

        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 30, y: 32, width: 10, height: 10)).fill()
        NSBezierPath(ovalIn: NSRect(x: 48, y: 32, width: 10, height: 10)).fill()
    }
}
