import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The full app window: Home, History, Class notes, Suggestions, Appearance, Settings.
final class MainWindowController {
    enum Page: String, CaseIterable, Identifiable {
        case home = "Home", schedule = "Schedule", brief = "Morning brief", history = "History", classes = "Class notes", suggestions = "Suggestions",
             appearance = "Appearance", settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .home: return "house"
            case .brief: return "sunrise"
            case .schedule: return "calendar.day.timeline.left"
            case .history: return "clock"
            case .classes: return "book"
            case .suggestions: return "pin"
            case .appearance: return "paintpalette"
            case .settings: return "gearshape"
            }
        }
    }

    private var window: NSWindow?
    private let state: AppState
    private let selection = PageSelection()

    init(state: AppState) { self.state = state }

    func show(page: Page = .home) {
        state.reloadFiles()
        selection.page = page
        if window == nil {
            let root = MainView(state: state, selection: selection)
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = "DictateBar"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 900, height: 600))
            w.minSize = NSSize(width: 760, height: 480)
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class PageSelection: ObservableObject {
    @Published var page: MainWindowController.Page = .home
}

private struct MainView: View {
    @ObservedObject var state: AppState
    @ObservedObject var selection: PageSelection

    var body: some View {
        NavigationSplitView {
            List(MainWindowController.Page.allCases, selection: $selection.page) { page in
                Label(page.rawValue, systemImage: page.icon).tag(page)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch selection.page {
            case .home: HomeView(state: state)
            case .brief: BriefView(state: state)
            case .schedule: ScheduleView(state: state)
            case .history: HistoryView(state: state)
            case .classes: ClassesView(state: state)
            case .suggestions: SuggestionsView(state: state)
            case .appearance: AppearanceView(state: state)
            case .settings: SettingsPage(state: state)
            }
        }
    }
}

// MARK: - Home

private struct HomeView: View {
    @ObservedObject var state: AppState
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Circle().fill(state.isRecording ? Color.red : Color.green).frame(width: 10, height: 10)
                Text(state.statusText).font(.headline)
                Spacer()
                Text(state.usageCodex).font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                action(state.isRecording ? "Stop" : "Record", "mic.fill", "⌥R") { state.actions.record() }
                action("Record class", "waveform", "⌥C") { state.actions.recordClass() }
                action("Clipboard prompt", "doc.on.clipboard", "⌥V") { state.actions.clipboardPrompt() }
                action("Notes", "note.text", "⌥N") { state.actions.notes() }
                action("Grade", "checkmark.seal", "⌥G") { state.actions.grade() }
                action("Paste class notes", "arrow.down.doc", "⌥P") { state.actions.pasteNotes() }
            }

            GroupBox("In the menu bar now") {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $draft)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 160)
                    HStack {
                        Text("Edit and press Use to put your own text in the bar.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Reload") { draft = state.currentText }
                        Button("Use this text") { state.actions.useText(draft) }.keyboardShortcut(.defaultAction)
                    }
                }
            }

            GroupBox("Suggested next") {
                if let s = state.suggestion {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.title).bold()
                            Text("\(s.subject)\(s.due.map { " · due \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary)
                            if !s.details.isEmpty { Text(s.details).font(.caption) }
                        }
                        Spacer()
                        Button("Write it") { state.actions.writeSuggestion() }
                        Button("Next") { state.actions.nextSuggestion() }
                        Button("Done") { state.actions.doneSuggestion() }
                    }
                } else {
                    Text("Nothing yet — record a class or sync Canvas.").foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(20)
        .onAppear { draft = state.currentText }
        .onChange(of: state.currentText) { _, new in draft = new }
    }

    private func action(_ title: String, _ icon: String, _ key: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.caption)
                Text(key).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
        }
    }
}

// MARK: - Schedule

private struct ScheduleView: View {
    @ObservedObject var state: AppState
    @State private var settings = Settings.load()
    @State private var now = Date()
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("Add schedule PDF…") { pickFiles() }
                Text("Bell schedule, cycle-day calendar, your timetable — one or several files. The AI reads them and builds the schedule; re-add any time to replace it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !state.scheduleStatus.isEmpty {
                Text(state.scheduleStatus).font(.caption).foregroundStyle(.secondary)
            }

            if let schedule = state.schedule {
                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(headline(schedule)).font(.title3.bold())
                            Text(schedule.summary(at: now)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Today is", selection: Binding(
                            get: { schedule.cycleLabel(for: now) ?? schedule.cycleLabels.first ?? "" },
                            set: { state.actions.setCycleDay($0) })) {
                            ForEach(schedule.cycleLabels, id: \.self) { Text("Day \($0)").tag($0) }
                        }.frame(width: 160)
                    }
                }

                let slots = schedule.slots(for: now)
                if slots.isEmpty {
                    Text("No classes today.").foregroundStyle(.secondary)
                } else {
                    List(slots, id: \.start) { slot in
                        HStack {
                            Text(time(slot.start) + " – " + time(slot.end)).monospacedDigit().frame(width: 120, alignment: .leading)
                            Text(slot.period.name).frame(width: 110, alignment: .leading).foregroundStyle(.secondary)
                            Text(slot.className == "Free" ? "Free" : schedule.short(slot.className)).bold(isCurrent(slot))
                            Spacer()
                            if isCurrent(slot) { Text("now").font(.caption).foregroundStyle(.green) }
                            else if schedule.next(after: now) == slot { Text("next").font(.caption).foregroundStyle(.blue) }
                        }
                        .listRowBackground(isCurrent(slot) ? Color.accentColor.opacity(0.12) : nil)
                    }
                }

                GroupBox("Alerts") {
                    HStack {
                        Toggle("Notify before each class", isOn: $settings.classAlerts)
                        Stepper("\(settings.alertMinutes) min before", value: $settings.alertMinutes, in: 1...30)
                        Spacer()
                        Toggle("Recording a class uses the scheduled class as its subject", isOn: $settings.subjectFromSchedule)
                    }
                }
                if let notes = schedule.notes, !notes.isEmpty {
                    Text("Notes from import: " + notes).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Spacer()
                Text("No schedule yet. Add your school's schedule PDF and DictateBar will show what class is next, alert you before it, and use it as context.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(16)
        .onReceive(tick) { now = $0 }
        .onChange(of: settings) { _, new in new.save(); state.actions.applySettings(new) }
    }

    private func headline(_ s: Schedule) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: now) + (s.cycleLabel(for: now).map { " · Day \($0)" } ?? " · No school")
    }

    private func isCurrent(_ slot: Schedule.Slot) -> Bool { slot.start <= now && now < slot.end }

    private func time(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm"
        return f.string(from: d)
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .plainText]
        panel.message = "Choose your bell schedule and/or cycle-day calendar"
        if panel.runModal() == .OK { state.actions.importSchedule(panel.urls) }
    }
}

// MARK: - Morning brief

private struct BriefView: View {
    @ObservedObject var state: AppState
    @State private var settings = Settings.load()
    @State private var selected: URL?

    private var today: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("Every morning at", isOn: $settings.briefEnabled)
                Stepper(String(format: "%d:%02d", settings.briefHour, settings.briefMinute), value: $settings.briefHour, in: 4...11)
                Stepper("min", value: $settings.briefMinute, in: 0...55, step: 5).labelsHidden()
                Text(String(format: "%02d", settings.briefMinute)).monospacedDigit()
                Spacer()
                Button("Generate now") { state.actions.generateBrief() }
            }
            Text("Reads your latest class notes, suggestions and Canvas due dates, then pulls the exact pages or units mentioned (\"reading quiz on pages 40–80\") from the synced files so you can review before class.")
                .font(.caption).foregroundStyle(.secondary)
            HSplitView {
                List(state.briefs, selection: $selected) { b in
                    HStack {
                        Text(b.name)
                        if b.name == today { Text("today").font(.caption).foregroundStyle(.green) }
                    }.tag(b.id)
                }
                .frame(minWidth: 150, maxWidth: 200)
                ScrollView {
                    if let b = state.briefs.first(where: { $0.id == selected }) ?? state.briefs.first {
                        Text(b.text).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    } else {
                        Text("No brief yet. It runs on its own each morning, or press Generate now.").foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(16)
        .onAppear { selected = state.briefs.first?.id }
        .onChange(of: settings) { _, new in new.save(); state.actions.applySettings(new) }
    }
}

// MARK: - History

private struct HistoryView: View {
    @ObservedObject var state: AppState
    @State private var selected: AppState.HistoryEntry.ID?

    var body: some View {
        HSplitView {
            List(state.history, selection: $selected) { entry in
                VStack(alignment: .leading) {
                    Text(entry.header).font(.caption).foregroundStyle(.secondary)
                    Text(entry.output.isEmpty ? entry.input : entry.output).lineLimit(2)
                }.tag(entry.id)
            }
            .frame(minWidth: 280)
            VStack(alignment: .leading, spacing: 10) {
                if let e = state.history.first(where: { $0.id == selected }) {
                    Text(e.header).font(.caption).foregroundStyle(.secondary)
                    Text("Input").font(.headline)
                    ScrollView { Text(e.input).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 160)
                    Text("Output").font(.headline)
                    ScrollView { Text(e.output).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    HStack {
                        Spacer()
                        Button("Put in menu bar") { state.actions.useText(e.output) }.disabled(e.output.isEmpty)
                    }
                } else {
                    Text("Select a run. Every recording, prompt, notes and grade job is kept here.").foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Class notes

private struct ClassesView: View {
    @ObservedObject var state: AppState
    @State private var selected: URL?

    var body: some View {
        HSplitView {
            List(state.classNotes, selection: $selected) { note in
                VStack(alignment: .leading) {
                    Text(note.name)
                    Text(note.subject).font(.caption).foregroundStyle(.secondary)
                }.tag(note.id)
            }
            .frame(minWidth: 240)
            VStack(alignment: .leading, spacing: 10) {
                if let n = state.classNotes.first(where: { $0.id == selected }) {
                    ScrollView { Text(n.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    HStack {
                        Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(n.text, forType: .string) }
                        Button("Open file") { NSWorkspace.shared.open(n.id) }
                        Spacer()
                        Button("Put in menu bar") { state.actions.useText(n.text) }
                    }
                } else {
                    Text(state.classNotes.isEmpty ? "No recorded classes yet. Press ⌥C at the start of class." : "Select a class.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Suggestions

private struct SuggestionsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        List {
            Section("To do") {
                ForEach(state.suggestions.filter { !$0.done }) { s in row(s) }
            }
            Section("Done") {
                ForEach(state.suggestions.filter { $0.done }) { s in row(s) }
            }
        }
    }

    private func row(_ s: Suggestion) -> some View {
        HStack {
            Button { state.actions.toggleSuggestionDone(s) } label: {
                Image(systemName: s.done ? "checkmark.circle.fill" : "circle")
            }.buttonStyle(.plain)
            VStack(alignment: .leading) {
                Text(s.title).strikethrough(s.done)
                Text("\(s.subject) · \(s.source)\(s.due.map { " · due \($0)" } ?? "")").font(.caption).foregroundStyle(.secondary)
                if !s.details.isEmpty { Text(s.details).font(.caption) }
            }
            Spacer()
        }
    }
}

extension Suggestion: Identifiable {}

// MARK: - Appearance

private struct AppearanceView: View {
    @ObservedObject var state: AppState
    @State private var settings = Settings.load()

    var body: some View {
        Form {
            Section("Preview") {
                PreviewLine(appearance: settings.appearance)
            }
            Section("Colors") {
                ColorPicker("Text", selection: HexColorBinding.make($settings.appearance.textColor, fallback: .labelColor))
                ColorPicker("Already typed", selection: HexColorBinding.make($settings.appearance.typedColor, fallback: .tertiaryLabelColor))
                ColorPicker("Next-letter highlight", selection: HexColorBinding.make($settings.appearance.highlightColor, fallback: .controlAccentColor))
                ColorPicker("Next-letter text", selection: HexColorBinding.make($settings.appearance.highlightTextColor, fallback: .white))
                ColorPicker("Suggestion", selection: HexColorBinding.make($settings.appearance.suggestionColor, fallback: .secondaryLabelColor))
                Text("System colors: black text in light mode, white in dark mode, always white on a full-screen app's black band.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Use system colors") {
                    settings.appearance.textColor = ""; settings.appearance.typedColor = ""
                    settings.appearance.highlightColor = ""; settings.appearance.suggestionColor = ""
                    settings.appearance.highlightTextColor = "#FFFFFF"
                }
            }
            Section("Text") {
                Picker("Font", selection: $settings.appearance.fontStyle) {
                    Text("Monospaced").tag(Appearance.FontStyle.mono)
                    Text("System").tag(Appearance.FontStyle.system)
                    Text("Rounded").tag(Appearance.FontStyle.rounded)
                }
                Slider(value: $settings.appearance.fontSize, in: 10...16, step: 1) { Text("Size  \(Int(settings.appearance.fontSize)) pt") }
            }
            Section("Background") {
                Picker("Style", selection: $settings.appearance.background) {
                    Text("Hide app menus (menu bar colour)").tag(Appearance.Background.hideMenus)
                    Text("None (plain text)").tag(Appearance.Background.none)
                    Text("Blurred pill").tag(Appearance.Background.pill)
                    Text("Solid color").tag(Appearance.Background.solid)
                }
                if settings.appearance.background == .solid {
                    ColorPicker("Color", selection: HexColorBinding.make($settings.appearance.backgroundColor, fallback: .black))
                    Slider(value: $settings.appearance.backgroundOpacity, in: 0.1...1) { Text("Opacity") }
                }
                if settings.appearance.background == .pill || settings.appearance.background == .solid {
                    Slider(value: $settings.appearance.cornerRadius, in: 0...11, step: 1) { Text("Corner radius") }
                }
            }
            Section("Layout") {
                Toggle("Show the suggestion at the right of the line", isOn: $settings.appearance.showSuggestion)
                Toggle("Line may cover the front app's menus", isOn: $settings.coverAppMenus)
                Stepper(settings.lineChars == 0 ? "Width: automatic" : "Width: \(settings.lineChars) characters",
                        value: $settings.lineChars, in: 0...200, step: 5)
            }
            Section {
                Button("Reset appearance") { settings.appearance = Appearance() }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings) { _, new in new.save(); state.actions.applySettings(new) }
    }
}

/// A mock of the menu bar line so changes are visible before you look up.
private struct PreviewLine: View {
    let appearance: Appearance

    var body: some View {
        let sample = NSMutableAttributedString()
        let f = appearance.font
        sample.append(NSAttributedString(string: "The quick ", attributes: [.font: f, .foregroundColor: appearance.typed]))
        sample.append(NSAttributedString(string: "b", attributes: [.font: f, .foregroundColor: appearance.highlightText, .backgroundColor: appearance.highlight]))
        sample.append(NSAttributedString(string: "rown fox jumps over the lazy dog", attributes: [.font: f, .foregroundColor: appearance.text]))
        sample.append(NSAttributedString(string: "     📌 ", attributes: [.font: f]))
        sample.append(NSAttributedString(string: "Essay draft", attributes: [.font: f, .foregroundColor: appearance.text]))
        sample.append(NSAttributedString(string: " · Fri", attributes: [.font: f, .foregroundColor: appearance.suggestion]))
        return HStack {
            Text(AttributedString(sample))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(previewBackground)
                .clipShape(RoundedRectangle(cornerRadius: appearance.cornerRadius))
            Spacer()
        }
        .padding(6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var previewBackground: some View {
        switch appearance.background {
        case .none: Color.clear
        case .hideMenus: Color(nsColor: .windowBackgroundColor)
        case .pill: Color(nsColor: .controlBackgroundColor).opacity(0.8)
        case .solid: Color(nsColor: appearance.backgroundNSColor)
        }
    }
}

// MARK: - Settings page

private struct SettingsPage: View {
    @ObservedObject var state: AppState
    @State private var settings = Settings.load()
    private let subjects = Settings.availableSubjects()

    var body: some View {
        Form {
            Section("Class") {
                Picker("Subject", selection: $settings.subject) {
                    Text("None (AI infers from request)").tag("")
                    ForEach(subjects, id: \.self) { Text($0).tag($0) }
                }
                TextField("Grade level (e.g. 10th grade)", text: $settings.gradeLevel)
            }
            Section("AI") {
                Picker("Cleanup / notes / grading", selection: $settings.aiProvider) {
                    Text("Codex (ChatGPT account)").tag(Settings.Provider.codex)
                    Text("Claude (Claude account)").tag(Settings.Provider.claude)
                }
                TextField("Codex model (blank = Codex default)", text: $settings.codexModel)
                TextField("Claude model", text: $settings.claudeModel)
                TextField("Whisper model (base.en / small.en)", text: $settings.whisperModel)
                Text(state.usageCodex).font(.caption).foregroundStyle(.secondary)
                Text(state.usageClaude).font(.caption).foregroundStyle(.secondary)
            }
            Section("Keys & behaviour") {
                Picker("Hotkey modifier", selection: $settings.hotkeyModifier) {
                    Text("Option").tag(Settings.Modifier.option)
                    Text("Control + Option").tag(Settings.Modifier.controlOption)
                }
                Toggle("Caps Lock auto-types the guide text", isOn: $settings.capsLockAutoType)
                Toggle("Open DictateBar at login", isOn: $settings.launchAtLogin)
                Stepper("Sync Canvas every \(Int(settings.syncHours)) h", value: $settings.syncHours, in: 1...24)
            }
            Section("Canvas & setup") {
                Text(subjects.isEmpty ? "Not connected." : "\(subjects.count) courses synced.").foregroundStyle(.secondary)
                HStack {
                    Button("Sync Canvas now") { state.actions.syncCanvas() }
                    Button("Sync calendar now") { state.actions.syncCalendar() }
                    Button("Setup…") { state.actions.openSetup() }
                }
            }
            Text("⌥R record · ⌥C class · ⌥P paste notes · ⌥V clipboard · ⌥N notes · ⌥G grade · ⌥W write suggestion · ⌥J next · ⌥D done · ⌥Space pause · ⌥H hide · ⌥O this window")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onChange(of: settings) { _, new in new.save(); state.actions.applySettings(new) }
    }
}
