import AppKit

/// A transparent panel that floats over the menu bar (between the front app's
/// menus and the notch) and shows the typing line, with the suggestion right-aligned.
final class OverlayWindow: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let trailing = NSTextField(labelWithString: "")
    private let blur = NSVisualEffectView()
    var onClick: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 22),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        isMovableByWindowBackground = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let content = NSView()
        contentView = content
        content.wantsLayer = true
        content.layer?.masksToBounds = true

        blur.material = .menu
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.isHidden = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(blur)

        for field in [label, trailing] {
            field.lineBreakMode = .byClipping
            field.maximumNumberOfLines = 1
            field.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(field)
        }
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: content.leadingAnchor), blur.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            blur.topAnchor.constraint(equalTo: content.topAnchor), blur.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            trailing.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            trailing.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            trailing.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
        ])
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func mouseDown(with event: NSEvent) { onClick?() }

    func apply(_ appearance: Appearance) {
        label.font = appearance.font
        trailing.font = appearance.font
        contentView?.layer?.cornerRadius = appearance.cornerRadius
        switch appearance.background {
        case .none:
            blur.isHidden = true
            contentView?.layer?.backgroundColor = nil
        case .pill:
            blur.isHidden = false
            contentView?.layer?.backgroundColor = nil
        case .solid:
            blur.isHidden = true
            contentView?.layer?.backgroundColor = appearance.backgroundNSColor.cgColor
        }
    }

    func show(text: NSAttributedString, trailing trailingText: NSAttributedString?, x: ClosedRange<CGFloat>, on screen: NSScreen) {
        label.attributedStringValue = text
        trailing.attributedStringValue = trailingText ?? NSAttributedString()
        trailing.isHidden = trailingText == nil
        let height: CGFloat = 22
        let menuBar = max(24, min(screen.frame.maxY - screen.visibleFrame.maxY, 44))
        let y = screen.frame.maxY - menuBar + (menuBar - height) / 2
        setFrame(NSRect(x: x.lowerBound, y: y, width: x.upperBound - x.lowerBound, height: height), display: true)
        orderFrontRegardless()
    }
}
