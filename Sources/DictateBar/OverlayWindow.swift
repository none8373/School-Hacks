import AppKit

/// A transparent panel that floats over the menu bar (between the front app's
/// menus and the notch) and shows the typing line as plain text.
final class OverlayWindow: NSPanel {
    private let label = NSTextField(labelWithString: "")
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

        // Plain text straight on the menu bar: no pill, no border. Colors follow the
        // system appearance (white in dark mode, near-black in light mode).
        let pill = NSView()
        contentView = pill

        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) { onClick?() }

    func show(text: NSAttributedString, x: ClosedRange<CGFloat>, on screen: NSScreen) {
        label.attributedStringValue = text
        let height: CGFloat = 22
        let menuBar = max(24, min(screen.frame.maxY - screen.visibleFrame.maxY, 44))
        let y = screen.frame.maxY - menuBar + (menuBar - height) / 2
        setFrame(NSRect(x: x.lowerBound, y: y, width: x.upperBound - x.lowerBound, height: height), display: true)
        orderFrontRegardless()
    }
}
