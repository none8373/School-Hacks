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
    /// Second strip for the right side of the notch, used in full-screen "band" mode.
    private let overlayRight = OverlayWindow()
    private let menu = NSMenu()
    private let playPauseItem = NSMenuItem()
    private let hideItem = NSMenuItem()
    private let recordItem = NSMenuItem()
    private let syncItem = NSMenuItem()
    private let statusLine = NSMenuItem()
    private let scheduleLine = NSMenuItem()

    /// Handlers the app wires up.
    var onPlayPause: (() -> Void)?
    var onHide: (() -> Void)?
    var onRecord: (() -> Void)?
    var onSync: (() -> Void)?
    var onRestart: (() -> Void)?
    var onClipboard: (() -> Void)?
    var onNotes: (() -> Void)?
    var onGrade: (() -> Void)?
    var onPage: (() -> Void)?
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
            overlayRight.apply(appearance)
            regrow()
            render()
        }
    }
    /// Info bar at the left of the strip: Canvas assignment, class recommendation, next class.
    var suggestion: Suggestion? { didSet { render() } }
    var classSuggestion: Suggestion? { didSet { render() } }
    var scheduleInfo: String? { didSet { render() } }
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
        // Left click opens the app window; right click (or Control-click) shows the menu.
        item.button?.target = self
        item.button?.action = #selector(statusButtonClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        overlay.onClick = { [weak self] in self?.onOpenWindow?() }
        render()
        regrow()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.regrow() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] _ in self?.regrow() }
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.pollMenuBarVisibility() }
    }

    // MARK: Measuring free space

    private var gap: ClosedRange<CGFloat> = 0...0
    /// Hidden while a full-screen app has the menu bar tucked away…
    private var menuBarVisible = true
    /// …unless the Mac has a notch: then the empty black band at the top is ours to fill.
    private var bandMode = false
    private var visibilityTimer: Timer?
    private var pendingState: (visible: Bool, band: Bool)?
    private var pendingCount = 0
    private var overlayChars = 0
    private var statusChars = 40
    private var measureTimer: Timer?
    private let minOverlayChars = 15
    private var charWidth: CGFloat { appearance.charWidth }

    private var usingOverlay: Bool { overlayChars >= minOverlayChars }

    /// The line flows left-of-notch first, then continues in the status item on the right.
    private var effectiveLineChars: Int {
        let auto = bandMode ? bandLeftChars + bandRightChars : overlayChars
        return lineChars > 0 ? min(lineChars, max(auto, minOverlayChars)) : auto
    }

    // MARK: Full-screen band (notched Macs)

    private var bandLeft: ClosedRange<CGFloat> = 0...0
    private var bandRight: ClosedRange<CGFloat> = 0...0
    private var bandLeftChars = 0
    private var bandRightChars = 0

    private func measureBand(on screen: NSScreen) -> Bool {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return false }
        bandLeft = (left.minX + 10)...(left.maxX - 6)
        bandRight = (right.minX + 6)...(right.maxX - 10)
        bandLeftChars = Int((bandLeft.upperBound - bandLeft.lowerBound - 16) / charWidth)
        bandRightChars = Int((bandRight.upperBound - bandRight.lowerBound - 16) / charWidth)
        return bandLeftChars >= minOverlayChars
    }

    /// Re-measure soon (new text, screen change, another app came to the front).
    func regrow() {
        measureTimer?.invalidate()
        measureTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.measure()
        }
    }

    /// In a full-screen app the menu bar only appears while the mouse is at the top edge,
    /// and it is always drawn dark there, so the strip switches to white text.
    private func pollMenuBarVisibility() {
        // Our own status item is hidden together with the menu bar and visible when it slides
        // in — macOS reports that through the item window's occlusion state.
        let barShown = item.button?.window?.occlusionState.contains(.visible) ?? true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fullScreen = MenuBarSpace.frontWindowIsFullScreen()
            DispatchQueue.main.async {
                guard let self else { return }
                let screen = self.item.button?.window?.screen ?? NSScreen.screens.first
                // Full-screen app: bar hidden -> fill the black band; bar slid in -> normal strip
                // over the bar (we sit above it). Require two consecutive identical readings so
                // the slide animation can't make the strip flicker.
                let visible = !fullScreen || barShown
                let band = fullScreen && !barShown && (screen.map { self.measureBand(on: $0) } ?? false)
                if let pending = self.pendingState, pending.visible == visible, pending.band == band {
                    self.pendingCount += 1
                } else {
                    self.pendingState = (visible, band)
                    self.pendingCount = 1
                }
                guard self.pendingCount >= 2, visible != self.menuBarVisible || band != self.bandMode else { return }
                let dark: NSAppearance? = fullScreen ? NSAppearance(named: .darkAqua) : nil
                self.overlay.appearance = dark
                self.overlayRight.appearance = dark
                self.overlay.forceBlack = band
                self.overlayRight.forceBlack = band
                self.menuBarVisible = visible
                self.bandMode = band
                self.render()
                if visible { self.regrow() }
            }
        }
    }

    private func measure() {
        guard let screen = item.button?.window?.screen ?? NSScreen.screens.first else { return }
        let ourMinX = item.button?.window?.frame.minX
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let gap = MenuBarSpace.freeGap(on: screen, ourItemMinX: ourMinX, coverAppMenus: self.coverAppMenus)
            let overlayChars = Int((gap.upperBound - gap.lowerBound - 16) / self.charWidth)
            DispatchQueue.main.async {
                guard gap != self.gap || overlayChars != self.overlayChars else { return }
                self.gap = gap
                self.overlayChars = overlayChars
                self.render()
            }
        }
    }

    // MARK: Menu

    private func buildMenu() {
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        scheduleLine.isEnabled = false
        menu.addItem(scheduleLine)
        menu.addItem(.separator())
        add(NSMenuItem(), title: "Open DictateBar", key: "o", action: #selector(openWindowTapped))
        menu.addItem(.separator())

        add(playPauseItem, title: "Pause", key: " ", action: #selector(playPauseTapped))
        add(hideItem, title: "Hide line", key: "h", action: #selector(hideTapped))
        add(recordItem, title: "Record", key: "r", action: #selector(recordTapped))
        add(NSMenuItem(), title: "Use clipboard text as prompt", key: "v", action: #selector(clipboardTapped))
        add(NSMenuItem(), title: "Notes for current assignment", key: "n", action: #selector(notesTapped))
        add(NSMenuItem(), title: "Grade the front document", key: "g", action: #selector(gradeTapped))
        add(NSMenuItem(), title: "Write / revise this page", key: "e", action: #selector(pageTapped))
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
        scheduleLine.title = Schedule.load()?.summary() ?? "No schedule yet — add it in the app"
        scheduleLine.isHidden = false
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
    @objc private func pageTapped() { onPage?() }
    @objc private func settingsTapped() { onSettings?() }
    @objc private func setupTapped() { onSetup?() }
    @objc private func openWindowTapped() { onOpenWindow?() }

    @objc private func statusButtonClicked() {
        let event = NSApp.currentEvent
        let rightClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if rightClick {
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            onOpenWindow?()
        }
    }
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

        let info = (suggestionBarVisible && status == .idle) ? infoBar(font: font) : nil

        if bandMode, !isHidden, let screen = button.window?.screen ?? NSScreen.screens.first {
            // Full-screen app, menu bar hidden: fill the black band on both sides of the notch.
            let leftChars = charsThatFit(width: bandLeft.upperBound - bandLeft.lowerBound, info: info)
            let (left, right) = split(prefix: prefix, body: body, leftChars: leftChars, rightChars: bandRightChars)
            overlay.show(text: left, info: info, x: bandLeft, on: screen)
            overlayRight.show(text: right, info: nil, x: bandRight, on: screen)
            button.attributedTitle = NSAttributedString()
            return
        }
        overlayRight.orderOut(nil)

        if usingOverlay, !isHidden, menuBarVisible, let screen = button.window?.screen ?? NSScreen.screens.first {
            // Left strip: info bar, then as much text as fits before the notch (whole words);
            // the status item shows whole words that fit right of the notch.
            let leftChars = charsThatFit(width: gap.upperBound - gap.lowerBound, info: info)
            let (left, _) = split(prefix: prefix, body: body, leftChars: leftChars, rightChars: 0)
            overlay.show(text: left, info: info, x: gap, on: screen)
            button.attributedTitle = NSAttributedString()
        } else {
            overlay.orderOut(nil)
            // No room for a strip: keep the status item to the icon plus a short state marker.
            button.attributedTitle = isHidden ? NSAttributedString() : prefix
        }
    }
}

extension StatusItemController {
    /// Splits the line into what fits left of the notch and what continues right of it,
    /// cutting only at word boundaries so no word is torn in half.
    fileprivate func split(prefix: NSAttributedString, body: NSAttributedString, leftChars: Int, rightChars: Int)
        -> (NSAttributedString, NSAttributedString) {
        let limit = max(0, leftChars - prefix.length)
        var cut = min(limit, body.length)
        let text = body.string as NSString
        if cut < body.length {
            let lastSpace = text.range(of: " ", options: .backwards, range: NSRange(location: 0, length: cut))
            if lastSpace.location != NSNotFound, lastSpace.location > cut / 2 { cut = lastSpace.location + 1 }
        }
        let left = NSMutableAttributedString(attributedString: prefix)
        left.append(body.attributedSubstring(from: NSRange(location: 0, length: cut)))

        var rightLength = min(body.length - cut, max(0, rightChars))
        if cut + rightLength < body.length, rightLength > 0 {
            let lastSpace = text.range(of: " ", options: .backwards, range: NSRange(location: cut, length: rightLength))
            rightLength = lastSpace.location == NSNotFound ? 0 : lastSpace.location - cut
        }
        let right = rightLength >= 3 ? body.attributedSubstring(from: NSRange(location: cut, length: rightLength)) : NSAttributedString()
        return (left, right)
    }

    /// Characters of guide text that fit in a strip of `width` points after the info bar,
    /// measured in points so nothing runs under the notch.
    fileprivate func charsThatFit(width: CGFloat, info: NSAttributedString?) -> Int {
        let infoWidth = info.map { $0.size().width + 12 } ?? 0
        return max(0, Int((width - 16 - infoWidth) / charWidth))
    }

    /// "📌 ENG: HW 9/10 · Fri  ·  📝 Study for safety quiz  ·  ⏭ Chem 9:17 · 12m left"
    fileprivate func infoBar(font: NSFont) -> NSAttributedString? {
        let line = NSMutableAttributedString()
        func add(_ icon: String, _ text: String, _ tail: String = "") {
            if line.length > 0 { line.append(NSAttributedString(string: "  ·  ", attributes: [.font: font, .foregroundColor: appearance.suggestion])) }
            line.append(NSAttributedString(string: icon + " ", attributes: [.font: font]))
            line.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: appearance.text]))
            if !tail.isEmpty { line.append(NSAttributedString(string: tail, attributes: [.font: font, .foregroundColor: appearance.suggestion])) }
        }
        if let s = suggestion { add("📌", trim(s.title, 26), dueTag(s.due)) }
        if let c = classSuggestion, c.id != suggestion?.id { add("📝", trim(c.title, 26), dueTag(c.due)) }
        if let sched = scheduleInfo { add("⏭", sched) }
        return line.length > 0 ? line : nil
    }

    private func trim(_ s: String, _ max: Int) -> String {
        s.count > max ? String(s.prefix(max - 1)) + "…" : s
    }

    private func dueTag(_ due: String?) -> String {
        guard let due else { return "" }
        let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"
        let outF = DateFormatter(); outF.dateFormat = "EEE"
        return inF.date(from: due).map { " · " + outF.string(from: $0) } ?? ""
    }
}

/// NSMenuDelegate shim so titles refresh right before the menu opens.
private final class MenuRefresher: NSObject, NSMenuDelegate {
    private let refresh: () -> Void
    init(refresh: @escaping () -> Void) { self.refresh = refresh }
    func menuWillOpen(_ menu: NSMenu) { refresh() }
}
