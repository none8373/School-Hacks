import AppKit

/// A transparent panel that floats over the menu bar (between the front app's
/// menus and the notch) and shows the typing line, with the suggestion right-aligned.
final class OverlayWindow: NSPanel {
    private let label = NSTextField(labelWithString: "")
    private let leading = NSTextField(labelWithString: "")
    private let blur = NSVisualEffectView()
    private let tint = NSView()
    private var fullHeight = false
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
        // A few notches above the menu bar: some apps (Electron) paint their own band at +2.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 5)
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
        // Opaque wash the colour of the menu bar so app menu titles beneath are hidden.
        tint.wantsLayer = true
        tint.isHidden = true
        tint.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tint)

        for field in [label, leading] {
            field.lineBreakMode = .byClipping
            field.maximumNumberOfLines = 1
            field.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(field)
        }
        leading.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: content.leadingAnchor), blur.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            blur.topAnchor.constraint(equalTo: content.topAnchor), blur.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: content.leadingAnchor), tint.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tint.topAnchor.constraint(equalTo: content.topAnchor), tint.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            leading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            leading.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leading.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -8),
        ])
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func mouseDown(with event: NSEvent) { onClick?() }

    func apply(_ appearance: Appearance) {
        label.font = appearance.font
        leading.font = appearance.font
        contentView?.layer?.cornerRadius = appearance.background == .hideMenus ? 0 : appearance.cornerRadius
        fullHeight = appearance.background == .hideMenus
        tint.isHidden = appearance.background != .hideMenus
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
        case .hideMenus:
            blur.isHidden = false
            blur.material = .titlebar
            contentView?.layer?.backgroundColor = nil
        }
        updateTint()
    }

    /// Menu bar-ish colour that follows light/dark mode (and the black full-screen band).
    private func updateTint() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = forceBlack ? NSColor.black : (dark ? NSColor(white: 0.12, alpha: 0.92) : NSColor(white: 0.93, alpha: 0.92))
        tint.layer?.backgroundColor = color.cgColor
    }

    /// In a full-screen app the strip sits on the black notch band.
    var forceBlack = false { didSet { updateTint() } }

    override var appearance: NSAppearance? {
        didSet { updateTint() }
    }

    /// `info` sits at the left edge; `text` follows it and is clipped before the strip ends.
    func show(text: NSAttributedString, info: NSAttributedString?, x: ClosedRange<CGFloat>, on screen: NSScreen) {
        label.attributedStringValue = text
        leading.attributedStringValue = info ?? NSAttributedString()
        leading.isHidden = info == nil
        let menuBar = max(24, min(screen.frame.maxY - screen.visibleFrame.maxY, 44))
        let height: CGFloat = fullHeight ? menuBar : 22
        let y = screen.frame.maxY - menuBar + (menuBar - height) / 2
        setFrame(NSRect(x: x.lowerBound, y: y, width: x.upperBound - x.lowerBound, height: height), display: true)
        orderFrontRegardless()
    }
}
