import AppKit

/// Wires all the pieces together.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings = Settings.load()
    private let guide = TextGuide()
    private var statusItem: StatusItemController!
    private let watcher = OutputWatcher()
    private let eventTap = EventTap()
    private let recorder = Recorder()
    private let pipeline = Pipeline()
    private let sync = CanvasSync()
    private var accessibilityTimer: Timer?
    private let suggestions = SuggestionStore()
    private let calendar = CalendarSync()
    private let briefScheduler = BriefScheduler()
    private let alerts = ClassAlerts()
    private var classStartedAt: Date?
    private var classSubjectAtStart: String?
    private var lastClassNotes: String?
    private let state = AppState()
    private lazy var mainWindow = MainWindowController(state: state)
    private lazy var setupWindow: SetupWindowController = {
        let c = SetupWindowController()
        c.model.runCanvasSync = { [weak self] in
            self?.statusItem.status = .syncing
            self?.sync.runNow()
        }
        return c
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Paths.ensureFolders()
        statusItem = StatusItemController(guide: guide)
        statusItem.lineChars = settings.lineChars
        statusItem.coverAppMenus = settings.coverAppMenus
        statusItem.appearance = settings.appearance

        statusItem.onPlayPause = { [weak self] in self?.togglePlay() }
        statusItem.onHide = { [weak self] in self?.toggleHidden() }
        statusItem.onRecord = { [weak self] in self?.toggleRecording() }
        statusItem.onRestart = { [weak self] in self?.restart() }
        statusItem.onClipboard = { [weak self] in self?.promptFromClipboard() }
        statusItem.onNotes = { [weak self] in self?.showNotes() }
        statusItem.onGrade = { [weak self] in self?.gradeFrontDocument() }
        statusItem.onSettings = { [weak self] in self?.mainWindow.show(page: .settings) }
        statusItem.onOpenWindow = { [weak self] in self?.mainWindow.show() }
        wireState()
        statusItem.onSetup = { [weak self] in self?.setupWindow.show() }
        statusItem.onClassRecord = { [weak self] in self?.toggleClassRecording() }
        statusItem.onPasteNotes = { [weak self] in self?.pasteClassNotes() }
        statusItem.onWriteSuggestion = { [weak self] in self?.writeSuggestion() }
        statusItem.onNextSuggestion = { [weak self] in self?.suggestions.next(); self?.refreshSuggestionBar() }
        statusItem.onDoneSuggestion = { [weak self] in self?.suggestions.markCurrentDone(); self?.refreshSuggestionBar() }
        statusItem.onToggleSuggestionBar = { [weak self] in
            guard let self else { return }
            self.statusItem.suggestionBarVisible.toggle()
            self.refreshSuggestionBar()
        }
        statusItem.onCalendarSync = { [weak self] in self?.syncCalendar() }
        suggestions.mergeCanvas(CanvasAssignment.loadAll())
        refreshSuggestionBar()
        statusItem.onSync = { [weak self] in
            self?.statusItem.status = .syncing
            self?.sync.runNow()
        }

        reloadOutput()
        watcher.onChange = { [weak self] in self?.reloadOutput() }
        watcher.start()

        eventTap.modifier = settings.hotkeyModifier
        eventTap.onHotkey = { [weak self] hotkey in self?.handle(hotkey) }
        eventTap.onTyped = { [weak self] typed in self?.handle(typed) }
        eventTap.capsLockAutoType = settings.capsLockAutoType
        eventTap.onAutoType = { [weak self] in self?.nextCharacterForAutoType() }
        eventTap.onFlagsChanged = { [weak self] in self?.statusItem.render() }
        startEventTapWhenAllowed()

        sync.onFinished = { [weak self] result in self?.syncFinished(result) }
        sync.schedule(everyHours: settings.syncHours)
        LoginItem.apply(settings.launchAtLogin)
        briefScheduler.onDue = { [weak self] in self?.generateBrief() }
        briefScheduler.configure(enabled: settings.briefEnabled, hour: settings.briefHour, minute: settings.briefMinute)
        alerts.schedule = Schedule.load()
        alerts.enabled = settings.classAlerts
        alerts.minutesBefore = settings.alertMinutes
        alerts.start()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refreshSuggestionBar() }
        showSetupIfNeeded()
    }

    // MARK: Schedule

    private func importSchedule(_ files: [URL]) {
        guard !isBusy, !files.isEmpty else { return }
        statusItem.status = .thinking
        state.scheduleStatus = "Reading \(files.count) file(s) and building your schedule…"
        settings = Settings.load()
        pipeline.importSchedule(files: files, settings: settings) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let schedule):
                self.alerts.schedule = schedule
                self.statusItem.status = .message("Schedule imported: \(schedule.periods.count) periods, \(schedule.cycleLength)-day cycle")
                self.state.scheduleStatus = schedule.notes ?? ""
            case .failure(let error):
                self.statusItem.status = .error("Schedule: \(error.localizedDescription)")
                self.state.scheduleStatus = error.localizedDescription
            }
            self.publishState()
        }
    }

    private func setCycleDay(_ label: String) {
        guard var schedule = Schedule.load() else { return }
        schedule.setToday(label)
        schedule.save()
        alerts.schedule = schedule
        publishState()
    }

    /// The class the schedule says is happening right now, as a subject folder name.
    private var currentScheduledSubject: String? {
        guard settings.subjectFromSchedule, let current = Schedule.load()?.current(), current.className != "Free" else { return nil }
        return Settings.availableSubjects().first { $0 == current.className } ?? current.className
    }

    /// The daily brief: runs on schedule or from the Morning brief page.
    private func generateBrief() {
        guard !isBusy else { return }
        start(.brief)
    }

    /// First launch, or anything essential missing: open the setup window.
    private func showSetupIfNeeded() {
        let model = setupWindow.model
        model.refresh()
        if !settings.setupShown || !model.essentialsDone {
            settings.setupShown = true
            settings.save()
            setupWindow.show()
        }
    }

    // MARK: Main window state

    private func wireState() {
        state.actions.record = { [weak self] in self?.toggleRecording() }
        state.actions.recordClass = { [weak self] in self?.toggleClassRecording() }
        state.actions.clipboardPrompt = { [weak self] in self?.promptFromClipboard() }
        state.actions.notes = { [weak self] in self?.showNotes() }
        state.actions.grade = { [weak self] in self?.gradeFrontDocument() }
        state.actions.pasteNotes = { [weak self] in self?.pasteClassNotes() }
        state.actions.writeSuggestion = { [weak self] in self?.writeSuggestion() }
        state.actions.nextSuggestion = { [weak self] in self?.suggestions.next(); self?.refreshSuggestionBar() }
        state.actions.doneSuggestion = { [weak self] in self?.suggestions.markCurrentDone(); self?.refreshSuggestionBar() }
        state.actions.toggleSuggestionDone = { [weak self] s in self?.suggestions.toggleDone(s); self?.refreshSuggestionBar() }
        state.actions.useText = { [weak self] text in
            try? text.write(to: Paths.current, atomically: true, encoding: .utf8)
            self?.reloadOutput()
        }
        state.actions.syncCanvas = { [weak self] in self?.statusItem.status = .syncing; self?.sync.runNow() }
        state.actions.syncCalendar = { [weak self] in self?.syncCalendar() }
        state.actions.openSetup = { [weak self] in self?.setupWindow.show() }
        state.actions.applySettings = { [weak self] s in self?.apply(s) }
        state.actions.generateBrief = { [weak self] in self?.generateBrief() }
        state.actions.importSchedule = { [weak self] files in self?.importSchedule(files) }
        state.actions.setCycleDay = { [weak self] label in self?.setCycleDay(label) }
    }

    private func publishState() {
        state.reloadFiles()
        state.suggestion = suggestions.current
        state.suggestions = suggestions.items
        state.isRecording = recorder.isRecording
        switch statusItem.status {
        case .idle: state.statusText = statusItem.isPlaying ? "Following your typing" : "Paused"
        case .recording: state.statusText = statusItem.isClassRecording ? "Recording class…" : "Recording…"
        case .thinking: state.statusText = "Working on it…"
        case .syncing: state.statusText = "Syncing Canvas…"
        case .error(let m): state.statusText = "Error: \(m)"
        case .message(let m): state.statusText = m
        }
    }

    // MARK: Output text

    private func reloadOutput() {
        let text = (try? String(contentsOf: Paths.current, encoding: .utf8)) ?? ""
        guide.load(text)
        statusItem.isPlaying = true
        statusItem.status = .idle
        statusItem.regrow()
        publishState()
    }

    private func restart() {
        guide.moveTo(0)
        statusItem.render()
    }

    // MARK: Play / hide

    private func togglePlay() {
        statusItem.isPlaying.toggle()
    }

    private func toggleHidden() {
        statusItem.isHidden.toggle()
        refreshSuggestionBar()
    }

    // MARK: Hotkeys and typing

    private func handle(_ hotkey: EventTap.Hotkey) {
        switch hotkey {
        case .record: toggleRecording()
        case .clipboard: promptFromClipboard()
        case .notes: showNotes()
        case .grade: gradeFrontDocument()
        case .classRecord: toggleClassRecording()
        case .pasteNotes: pasteClassNotes()
        case .writeSuggestion: writeSuggestion()
        case .nextSuggestion: suggestions.next(); refreshSuggestionBar()
        case .doneSuggestion: suggestions.markCurrentDone(); refreshSuggestionBar()
        case .openWindow: mainWindow.show()
        case .playPause: togglePlay()
        case .hide: toggleHidden()
        case .wordBack: guide.previousWord()
        case .wordForward: guide.nextWord()
        case .sentenceBack: guide.previousSentence()
        case .sentenceForward: guide.nextSentence()
        }
        statusItem.render()
    }

    private func handle(_ typed: EventTap.Typed) {
        guard statusItem.isPlaying, statusItem.status == .idle else { return }
        switch typed {
        case .character(let c): guide.typed(c)
        case .backspace: guide.backspace()
        }
        statusItem.render()
    }

    /// Caps Lock mode: hand the event tap the next guide character and move the marker past it.
    private func nextCharacterForAutoType() -> Character? {
        guard statusItem.isPlaying, statusItem.status == .idle, !guide.isFinished else { return nil }
        let c = guide.chars[guide.cursor]
        guide.moveTo(guide.cursor + 1)
        statusItem.render()
        return c
    }

    private func startEventTapWhenAllowed() {
        if EventTap.isTrusted(prompt: true), eventTap.start() { return }
        // Not granted yet: keep checking until the user flips the switch in System Settings.
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] timer in
            guard let self else { return }
            if EventTap.isTrusted(prompt: false), self.eventTap.start() {
                timer.invalidate()
            }
        }
    }

    // MARK: Recording → pipeline

    private func toggleRecording() {
        if recorder.isRecording {
            if classStartedAt != nil { stopClassRecording() } else { stopRecording() }
        } else {
            startRecording()
        }
    }

    // MARK: Class recording

    private func toggleClassRecording() {
        if recorder.isRecording {
            if classStartedAt != nil { stopClassRecording() } else { stopRecording() }
        } else {
            startRecording(isClass: true)
        }
    }

    private func stopClassRecording() {
        guard let wav = recorder.stop(), let startedAt = classStartedAt else { return }
        classStartedAt = nil
        statusItem.isClassRecording = false
        statusItem.status = .thinking
        publishState()
        settings = Settings.load()
        if let scheduled = classSubjectAtStart { settings.subject = scheduled }
        pipeline.runClass(wav: wav, startedAt: startedAt, settings: settings) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let cls):
                self.lastClassNotes = cls.notes
                self.suggestions.add(cls.suggestions)
                self.refreshSuggestionBar()
                self.calendar.addClassSession(subject: cls.subject, start: startedAt, end: Date(),
                                              notesPath: cls.notesURL.path, summary: cls.summary)
                self.syncCalendar(quiet: true)
                self.reloadOutput()
            case .failure(let error):
                self.statusItem.status = .error(error.localizedDescription)
            }
        }
    }

    /// Puts the latest class notes on the clipboard and pastes them into the front app.
    private func pasteClassNotes() {
        let notes = lastClassNotes ?? latestClassNotesOnDisk()
        guard let notes, !notes.isEmpty else {
            statusItem.status = .error("No class notes yet — record a class with Option+C")
            return
        }
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(notes, forType: .string)
        DocumentCapture.paste()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let previous { pasteboard.clearContents(); pasteboard.setString(previous, forType: .string) }
        }
    }

    private func latestClassNotesOnDisk() -> String? {
        let folder = settings.subject.isEmpty ? Paths.classes : Paths.classes.appendingPathComponent(settings.subject)
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        let notes = files.compactMap { $0 as? URL }.filter { $0.lastPathComponent.hasSuffix(".notes.md") }
        let newest = notes.max { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
        return newest.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    // MARK: Suggestions

    private func refreshSuggestionBar() {
        let open = suggestions.openItems
        statusItem.suggestion = open.first { $0.source == "canvas" } ?? suggestions.current
        statusItem.classSuggestion = open.first { $0.source == "class" }
        statusItem.scheduleInfo = Schedule.load()?.compact()
        publishState()
    }

    /// Turns the current suggestion into a finished writing piece via the normal cleanup path.
    private func writeSuggestion() {
        guard !isBusy, let current = suggestions.current else {
            if suggestions.current == nil { statusItem.status = .error("No suggestions yet — record a class or sync Canvas") }
            return
        }
        var request = "Write the following assignment for me, complete and ready to hand in: \(current.title)."
        if !current.details.isEmpty { request += " Details from class: \(current.details)." }
        if let name = current.canvasAssignment { request += " It is the Canvas assignment \"\(name)\" — follow its instructions and rubric exactly." }
        request += " Use my class notes in classes/ and the course material. Subject: \(current.subject)."
        start(.clean(request))
    }

    // MARK: Calendar

    private func syncCalendar(quiet: Bool = false) {
        calendar.syncAll(suggestions: suggestions.items) { [weak self] result in
            guard let self, !quiet else { return }
            switch result {
            case .success(let n): self.statusItem.status = .message("Calendar updated: \(n) events")
            case .failure(let error): self.statusItem.status = .error("Calendar: \(error.localizedDescription)")
            }
        }
    }

    private func startRecording(isClass: Bool = false) {
        guard statusItem.status != .thinking, statusItem.status != .syncing else { return }
        Recorder.requestPermission { [weak self] ok in
            guard let self else { return }
            guard ok else {
                self.statusItem.status = .error("Microphone access denied (System Settings → Privacy → Microphone)")
                return
            }
            let url = Paths.recordings.appendingPathComponent("\(Pipeline.timestamp()).wav")
            do {
                try self.recorder.start(to: url)
                self.classStartedAt = isClass ? Date() : nil
                self.classSubjectAtStart = isClass ? self.currentScheduledSubject : nil
                self.statusItem.isClassRecording = isClass
                self.statusItem.status = .recording
                self.publishState()
            } catch {
                self.statusItem.status = .error("Could not start recording: \(error.localizedDescription)")
            }
        }
    }

    private func stopRecording() {
        guard let wav = recorder.stop() else { return }
        statusItem.status = .thinking
        settings = Settings.load()
        pipeline.run(wav: wav, settings: settings) { [weak self] result in
            self?.finish(result)
        }
    }

    // MARK: Settings

    private func apply(_ updated: Settings) {
        settings = updated
        eventTap.modifier = updated.hotkeyModifier
        eventTap.capsLockAutoType = updated.capsLockAutoType
        statusItem.coverAppMenus = updated.coverAppMenus
        statusItem.lineChars = updated.lineChars
        statusItem.appearance = updated.appearance
        sync.schedule(everyHours: updated.syncHours)
        LoginItem.apply(updated.launchAtLogin)
        briefScheduler.configure(enabled: updated.briefEnabled, hour: updated.briefHour, minute: updated.briefMinute)
        alerts.enabled = updated.classAlerts
        alerts.minutesBefore = updated.alertMinutes
        statusItem.regrow()
    }

    // MARK: Text-based jobs (clipboard prompt, notes, grading)

    private var isBusy: Bool {
        statusItem.status == .thinking || statusItem.status == .recording || statusItem.status == .syncing
    }

    /// Whatever text is on the clipboard becomes the prompt, exactly as if it had been spoken.
    private func promptFromClipboard() {
        guard !isBusy else { return }
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusItem.status = .error("Clipboard is empty — copy some text first")
            return
        }
        start(.clean(text))
    }

    /// Study notes for the selected subject's current assignment or test.
    private func showNotes() {
        guard !isBusy else { return }
        start(.notes(""))
    }

    /// Select-all + copy in the front app, then grade that text against the Canvas rubric.
    private func gradeFrontDocument() {
        guard !isBusy else { return }
        statusItem.status = .thinking
        DocumentCapture.frontDocumentText { [weak self] text in
            guard let self else { return }
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.statusItem.status = .error("Couldn't copy the document — click into it, then try Option+G again")
                return
            }
            self.start(.grade(text))
        }
    }

    private func start(_ mode: Pipeline.Mode) {
        statusItem.status = .thinking
        publishState()
        settings = Settings.load()
        pipeline.run(mode, settings: settings) { [weak self] result in
            self?.finish(result)
        }
    }

    private func finish(_ result: Result<String, Error>) {
        switch result {
        case .success: reloadOutput()
        case .failure(let error): statusItem.status = .error(error.localizedDescription)
        }
        publishState()
    }

    // MARK: Sync

    private func syncFinished(_ result: Result<String, Error>) {
        switch result {
        case .success:
            if statusItem.status == .syncing { statusItem.status = .message("Canvas synced") }
            setupWindow.model.refresh()
            suggestions.mergeCanvas(CanvasAssignment.loadAll())
            refreshSuggestionBar()
            syncCalendar(quiet: true)
        case .failure(let error): statusItem.status = .error("Sync: \(error.localizedDescription)")
        }
    }
}
