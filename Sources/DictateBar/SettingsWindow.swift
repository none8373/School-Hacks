import AppKit
import SwiftUI

/// The Settings… window. Changes save to config.json as you make them.
final class SettingsWindowController {
    private var window: NSWindow?
    private let onChange: (Settings) -> Void
    private let onOpenSetup: () -> Void

    init(onChange: @escaping (Settings) -> Void, onOpenSetup: @escaping () -> Void) {
        self.onChange = onChange
        self.onOpenSetup = onOpenSetup
    }

    func show() {
        // Rebuilt every time so a fresh Canvas sync shows up in the subject list.
        window?.close()
        do {
            let view = SettingsView(settings: Settings.load(), subjects: Settings.availableSubjects(), openSetup: onOpenSetup) { [weak self] updated in
                updated.save()
                self?.onChange(updated)
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "DictateBar Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 480, height: 520))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @State var settings: Settings
    let subjects: [String]
    let openSetup: () -> Void
    let onSave: (Settings) -> Void

    var body: some View {
        Form {
            Section("Class") {
                Picker("Subject", selection: $settings.subject) {
                    Text("None (AI infers from request)").tag("")
                    ForEach(subjects, id: \.self) { Text($0).tag($0) }
                }
                if subjects.isEmpty {
                    Text("No courses yet — choose “Sync Canvas now” from the mic menu first.")
                        .font(.caption).foregroundStyle(.secondary)
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
            }
            Section("Keys & display") {
                Picker("Hotkey modifier", selection: $settings.hotkeyModifier) {
                    Text("Option").tag(Settings.Modifier.option)
                    Text("Control + Option").tag(Settings.Modifier.controlOption)
                }
                Toggle("Caps Lock auto-types the guide text", isOn: $settings.capsLockAutoType)
                Toggle("Line may cover the front app's menus", isOn: $settings.coverAppMenus)
                Toggle("Open DictateBar at login", isOn: $settings.launchAtLogin)
                Stepper("Sync Canvas every \(Int(settings.syncHours)) h", value: $settings.syncHours, in: 1...24)
            }
            Section("Canvas & setup") {
                Text(subjects.isEmpty ? "Not connected." : "\(subjects.count) courses synced.").foregroundStyle(.secondary)
                Button("Open setup (Canvas token, speech model, permissions)…") { openSetup() }
            }
            Text("⌥R record · ⌥C record class · ⌥P paste class notes · ⌥V clipboard prompt · ⌥N notes · ⌥G grade · ⌥W write suggestion · ⌥J next · ⌥D done · ⌥H hide")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(.bottom, 8)
        .onChange(of: settings) { _, updated in onSave(updated) }
    }
}
