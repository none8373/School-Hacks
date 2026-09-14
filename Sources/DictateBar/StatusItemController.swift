import AppKit

/// Owns the menu bar icon, the dropdown menu, and the typing line — which is drawn
/// in a floating strip over the empty part of the menu bar (left of the notch), or,
/// if that gap is too small, inside the status item itself.
final class StatusItemController {
    enum Status: Equatable {
        case idle, recording, thinking, syncing
        case error(String)
        case message(String)
    }

    var status: Status = .idle { didSet { render() } }
    var isPlaying = true { didSet { render() } }
    var isHidden = false { didSet { render() } }
    /// 0 = auto-size to the free space in the menu bar.
    var lineChars = 0
    var coverAppMenus = true

    let guide: TextGuide
    private let item: NSStatusItem
    private let overlay = OverlayWindow()
    private let menu = NSMenu()
    private let playPauseItem = NSMenuItem()
    private let hideItem = NSMenuItem()
    private let recordItem = NSMenuItem()
    private let syncItem = NSMenuItem()
    private let statusLine = NSMenuItem()

    /// Handlers the app wires up.
    var onPlayPause: (() -> Void)?
    var onHide: (() -> Void)?
    var onRecord: (() -> Void)?
    var onSync: (() -> Void)?
    var onRestart: (() -> Void)?
    var onClipboard: (() -> Void)?
    var onNotes: (() -> Void)?
    var onGrade: (() -> Void)?
    var onSettings: (() -> Void)?
    var onSetup: (() -> Void)?
    var onOpenWindow: (() -> Void)?
    var onClassRecord: (() -> Void)?
    var onPasteNotes: (() -> Void)?
    var onWriteSuggestion: (() -> Void)?
    var onNextSuggestion: (() -> Void)?
    var onDoneSuggestion: (() -> Void)?
    var onToggleSuggestionBar: (() -> Void)?
    var onCalendarSync: (() -> Void)?
    var isClassRecording = false
    var suggestionBarVisible: Bool {
        get { appearance.showSuggestion }
        set { appearance.showSuggestion = newValue }
    }
    var appearance = Appearance() {
        didSet {
            overlay.apply(appearance)
            regrow()
            render()
        }
    }
    /// Shown in the status item (right of the notch) when set and visible.
    var suggestion: Suggestion? { didSet { render() } }
    private let classItem = NSMenuItem()
    private let usageLine1 = NSMenuItem()
    private let usageLine2 = NSMenuItem()
    private let suggestionToggleItem = NSMenuItem()

    init(guide: TextGuide) {
        self.guide = guide
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "DictateBar")
        item.button?.imagePosition = .imageLeading
        buildMenu()
        item.menu = menu
        overlay.onClick = { [weak self] in self?.item.button?.performClick(nil) }
        render()
        regrow()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.regrow() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] _ in self?.regrow() }
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.pollMenuBarVisibility() }
    }

    // MARK: Measuring free space

    private var gap: ClosedRange<CGFloat> = 0...0
    /// Hidden while a full-screen app has the menu bar tucked away.
    private var menuBarVisible = true
    private var visibilityTimer: Timer?
    private var overlayChars = 0
    private var statusChars = 40
    private var measureTimer: Timer?
    private let minOverlayChars = 15
    private var charWidth: CGFloat { appearance.charWidth }

    private var usingOverlay: Bool { lineChars == 0 && overlayChars >= minOverlayChars }

    /// The line flows left-of-notch first, then continues in the status item on the right.
    private var effectiveLineChars: Int {
        if lineChars > 0 { return lineChars }
        return usingOverlay ? overlayChars + statusChars : statusChars
    }

    /// Re-measure soon (new text, screen change, another app came to the front).
    func regrow() {
        guard lineChars == 0 else { return }
        measureTimer?.invalidate()
        measureTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.measure()
        }
    }

    /// In a full-screen app the menu bar only appears while the mouse is at the top edge,
    /// and it is always drawn dark there, so the strip switches to white text.
    private func pollMenuBarVisibility() {
        let mouse = NSEvent.mouseLocation
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fullScreen = MenuBarSpace.frontWindowIsFullScreen()
            DispatchQueue.main.async {
                guard let self else { return }
                let screen = self.item.button?.window?.screen ?? NSScreen.screens.first
                let atTop = screen.map { mouse.y >= $0.frame.maxY - 30 } ?? true
                let visible = !fullScreen || atTop
                self.overlay.appearance = fullScreen ? NSAppearance(named: .darkAqua) : nil
                guard visible != self.menuBarVisible else { return }
                self.menuBarVisible = visible
                self.render()
                if visible { self.regrow() }
            }
        }
    }

    private func measure() {
        guard let screen = item.button?.window?.screen ?? NSScreen.screens.first else { return }
        // Step 1: shrink to icon-only so macOS shows every other icon; the space left
        // between the notch and our icon is then exactly what we may use on the right.
        statusChars = 0
        render()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            let ourMinX = self.item.button?.window?.frame.minX
            let rightArea = screen.auxiliaryTopRightArea
            DispatchQueue.global(qos: .userInitiated).async {
                let gap = MenuBarSpace.freeGap(on: screen, ourItemMinX: ourMinX, coverAppMenus: self.coverAppMenus)
                let overlayChars = Int((gap.upperBound - gap.lowerBound - 16) / self.charWidth)
                var statusChars = 0
                if let rightArea, let ourMinX {
                    statusChars = max(0, Int((ourMinX - rightArea.minX - 20) / self.charWidth))
                }
                DispatchQueue.main.async {
                    self.gap = gap
                    self.overlayChars = overlayChars
                    self.statusChars = statusChars
                    self.render()
                }
            }
        }
    }

    // MARK: Menu

    private func buildMenu() {
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        add(NSMenuItem(), title: "Open DictateBar", key: "o", action: #selector(openWindowTapped))
        menu.addItem(.separator())

        add(playPauseItem, title: "Pause", key: " ", action: #selector(playPauseTapped))
        add(hideItem, title: "Hide line", key: "h", action: #selector(hideTapped))
        add(recordItem, title: "Record", key: "r", action: #selector(recordTapped))
        add(NSMenuItem(), title: "Use clipboard text as prompt", key: "v", action: #selector(clipboardTapped))
        add(NSMenuItem(), title: "Notes for current assignment", key: "n", action: #selector(notesTapped))
        add(NSMenuItem(), title: "Grade the front document", key: "g", action: #selector(gradeTapped))
        menu.addItem(.separator())
        add(classItem, title: "Record class", key: "c", action: #selector(classTapped))
        add(NSMenuItem(), title: "Paste class notes", key: "p", action: #selector(pasteNotesTapped))
        add(NSMenuItem(), title: "Write suggested assignment", key: "w", action: #selector(writeSuggestionTapped))
        add(NSMenuItem(), title: "Next suggestion", key: "j", action: #selector(nextSuggestionTapped))
        add(NSMenuItem(), title: "Mark suggestion done", key: "d", action: #selector(doneSuggestionTapped))
        add(suggestionToggleItem, title: "Hide suggestion", key: "", action: #selector(toggleSuggestionBarTapped))
        add(NSMenuItem(), title: "Restart from beginning", key: "", action: #selector(restartTapped))
        menu.addItem(.separator())
        add(syncItem, title: "Sync Canvas now", key: "", action: #selector(syncTapped))
        add(NSMenuItem(), title: "Sync calendar now", key: "", action: #selector(calendarTapped))
        menu.addItem(.separator())
        usageLine1.isEnabled = false
        usageLine2.isEnabled = false
        menu.addItem(usageLine1)
        menu.addItem(usageLine2)
        add(NSMenuItem(), title: "Open current output", key: "", action: #selector(openOutput))
        add(NSMenuItem(), title: "Open library folder", key: "", action: #selector(openLibrary))
        add(NSMenuItem(), title: "Open history log", key: "", action: #selector(openHistory))
        add(NSMenuItem(), title: "Settings…", key: ",", action: #selector(settingsTapped))
        add(NSMenuItem(), title: "Setup…", key: "", action: #selector(setupTapped))
        add(NSMenuItem(), title: "Re-measure menu bar space", key: "", action: #selector(remeasure))
        menu.addItem(.separator())
        add(NSMenuItem(), title: "Quit DictateBar", key: "q", action: #selector(quit))
        menu.delegate = menuRefresher
    }

    private lazy var menuRefresher = MenuRefresher { [weak self] in self?.refreshMenuTitles() }

    private func add(_ menuItem: NSMenuItem, title: String, key: String, action: Selector) {
        menuItem.title = title
        menuItem.keyEquivalent = key
        menuItem.keyEquivalentModifierMask = [.option]
        menuItem.action = action
        menuItem.target = self
        menu.addItem(menuItem)
    }

    private func refreshMenuTitles() {
        playPauseItem.title = isPlaying ? "Pause" : "Play"
        hideItem.title = isHidden ? "Show line" : "Hide line"
        recordItem.title = status == .recording && !isClassRecording ? "Stop recording" : "Record"
        classItem.title = isClassRecording ? "Stop class recording" : "Record class"
        suggestionToggleItem.title = suggestionBarVisible ? "Hide suggestion" : "Show suggestion"
        usageLine1.title = "Usage — " + Usage.summary(provider: "codex")
        usageLine2.title = "Usage — " + Usage.summary(provider: "claude")
        syncItem.title = "Sync Canvas now  (\(CanvasSync.lastSyncDescription()))"
        syncItem.isEnabled = status != .syncing
        switch status {
        case .idle: statusLine.title = isPlaying ? "Following your typing" : "Paused"
        case .recording: statusLine.title = isClassRecording ? "Recording class… Option+C to stop" : "Recording… press Option+R to stop"
        case .thinking: statusLine.title = "Working on it…"
        case .syncing: statusLine.title = "Syncing Canvas…"
        case .error(let message): statusLine.title = "Error: \(message)"
        case .message(let message): statusLine.title = message
        }
    }

    @objc private func playPauseTapped() { onPlayPause?() }
    @objc private func hideTapped() { onHide?() }
    @objc private func recordTapped() { onRecord?() }
    @objc private func restartTapped() { onRestart?() }
    @objc private func clipboardTapped() { onClipboard?() }
    @objc private func notesTapped() { onNotes?() }
    @objc private func gradeTapped() { onGrade?() }
    @objc private func settingsTapped() { onSettings?() }
    @objc private func setupTapped() { onSetup?() }
    @objc private func openWindowTapped() { onOpenWindow?() }
    @objc private func classTapped() { onClassRecord?() }
    @objc private func pasteNotesTapped() { onPasteNotes?() }
    @objc private func writeSuggestionTapped() { onWriteSuggestion?() }
    @objc private func nextSuggestionTapped() { onNextSuggestion?() }
    @objc private func doneSuggestionTapped() { onDoneSuggestion?() }
    @objc private func toggleSuggestionBarTapped() { onToggleSuggestionBar?() }
    @objc private func calendarTapped() { onCalendarSync?() }
    @objc private func openHistory() { NSWorkspace.shared.open(History.url) }
    @objc private func syncTapped() { onSync?() }
    @objc private func openOutput() { NSWorkspace.shared.open(Paths.current) }
    @objc private func openLibrary() { NSWorkspace.shared.open(Paths.library) }
    @objc private func remeasure() { regrow() }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Rendering the line

    func render() {
        guard let button = item.button else { return }
        let font = appearance.font

        func styled(_ text: String, _ color: NSColor, background: NSColor? = nil) -> NSAttributedString {
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            if let background { attrs[.backgroundColor] = background }
            return NSAttributedString(string: text, attributes: attrs)
        }

        let prefix = NSMutableAttributedString()
        switch status {
        case .recording: prefix.append(styled(isClassRecording ? "● CLASS " : "● ", .systemRed))
        case .thinking: prefix.append(styled("… ", .systemOrange))
        case .syncing: prefix.append(styled("↻ ", .systemBlue))
        case .error: prefix.append(styled("⚠︎ ", .systemRed))
        case .message: prefix.append(styled("✓ ", .systemGreen))
        case .idle: if !isPlaying, !isHidden { prefix.append(styled("⏸ ", .secondaryLabelColor)) }
        }
        if NSEvent.modifierFlags.contains(.capsLock), status == .idle, !isHidden {
            prefix.append(styled("⇪AUTO ", .systemGreen))
        }

        let body = NSMutableAttributedString()
        if case .message(let message) = status {
            body.append(styled(String(message.prefix(max(effectiveLineChars, 12))), appearance.text))
        } else if case .error(let message) = status {
            body.append(styled(String(message.prefix(max(effectiveLineChars, 12))), appearance.text))
        } else if !isHidden {
            if guide.isEmpty {
                body.append(styled("(no text yet)", appearance.suggestion))
            } else {
                let w = guide.window(chars: effectiveLineChars)
                body.append(styled(w.typed, appearance.typed))
                body.append(styled(w.current, appearance.highlightText, background: appearance.highlight))
                body.append(styled(w.upcoming, appearance.text))
            }
        }

        if usingOverlay, !isHidden, menuBarVisible, let screen = button.window?.screen ?? NSScreen.screens.first {
            // Left strip gets the prefix, the first part of the text and, at its right end, the
            // suggestion. Cut at a word boundary so no word is torn in half by the notch.
            let showSuggestion = suggestion != nil && suggestionBarVisible && status == .idle
            let suggestionText = showSuggestion ? compactSuggestion(suggestion!, font: font, room: min(30, overlayChars / 3)) : nil
            let reserved = suggestionText.map { $0.length + 3 } ?? 0
            let limit = max(0, overlayChars - prefix.length - reserved)
            var cut = min(limit, body.length)
            if cut < body.length {
                let text = body.string as NSString
                let searchRange = NSRange(location: 0, length: cut)
                let lastSpace = text.range(of: " ", options: .backwards, range: searchRange)
                if lastSpace.location != NSNotFound, lastSpace.location > cut / 2 { cut = lastSpace.location + 1 }
            }
            let left = NSMutableAttributedString(attributedString: prefix)
            left.append(body.attributedSubstring(from: NSRange(location: 0, length: cut)))
            overlay.show(text: left, trailing: suggestionText, x: gap, on: screen)
            // Right of the notch: only whole words, or nothing.
            var rightLength = min(body.length - cut, statusChars)
            if cut + rightLength < body.length {
                let tail = body.string as NSString
                let lastSpace = tail.range(of: " ", options: .backwards, range: NSRange(location: cut, length: rightLength))
                rightLength = lastSpace.location == NSNotFound ? 0 : lastSpace.location - cut
            }
            button.attributedTitle = rightLength >= 3
                ? body.attributedSubstring(from: NSRange(location: cut, length: rightLength))
                : NSAttributedString()
        } else {
            overlay.orderOut(nil)
            prefix.append(body)
            button.attributedTitle = prefix
        }
    }
}

extension StatusItemController {
    /// "📌 ENG: HW 9/10 · Fri" squeezed into the space right of the notch.
    fileprivate func compactSuggestion(_ s: Suggestion, font: NSFont, room: Int) -> NSAttributedString {
        let room = max(8, room - 2)
        var due = ""
        if let d = s.due {
            let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"
            let outF = DateFormatter(); outF.dateFormat = "EEE"
            if let date = inF.date(from: d) { due = " · " + outF.string(from: date) }
        }
        var title = s.title
        if title.count + due.count > room {
            title = String(title.prefix(max(4, room - due.count - 1))) + "…"
        }
        let line = NSMutableAttributedString(string: "📌 ", attributes: [.font: font])
        line.append(NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: appearance.text]))
        line.append(NSAttributedString(string: due, attributes: [.font: font, .foregroundColor: appearance.suggestion]))
        return line
    }
}

/// NSMenuDelegate shim so titles refresh right before the menu opens.
private final class MenuRefresher: NSObject, NSMenuDelegate {
    private let refresh: () -> Void
    init(refresh: @escaping () -> Void) { self.refresh = refresh }
    func menuWillOpen(_ menu: NSMenu) { refresh() }
}
