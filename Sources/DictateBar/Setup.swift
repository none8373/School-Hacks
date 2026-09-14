import AppKit
import AVFoundation
import EventKit
import SwiftUI

/// Everything a fresh Mac needs before DictateBar works, with buttons that fix each item.
final class SetupModel: ObservableObject {
    enum State: Equatable { case unknown, ok, missing, working(String), failed(String) }

    @Published var whisper: State = .unknown
    @Published var model: State = .unknown
    @Published var ai: State = .unknown
    @Published var python: State = .unknown
    @Published var canvas: State = .unknown
    @Published var microphone: State = .unknown
    @Published var accessibility: State = .unknown
    @Published var calendar: State = .unknown

    @Published var canvasURL = ""
    @Published var canvasToken = ""
    @Published var provider: Settings.Provider = .codex
    @Published var log = ""

    var runCanvasSync: (() -> Void)?

    var essentialsDone: Bool { whisper == .ok && model == .ok && ai == .ok }

    private let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }

    func refresh() {
        let settings = Settings.load()
        provider = settings.aiProvider
        whisper = FileManager.default.isExecutableFile(atPath: settings.resolvedWhisperPath) ? .ok : .missing
        model = FileManager.default.fileExists(atPath: settings.whisperModelFile.path) ? .ok : .missing
        let aiPath = settings.aiProvider == .codex ? settings.resolvedCodexPath : settings.resolvedClaudePath
        ai = FileManager.default.isExecutableFile(atPath: aiPath) ? .ok : .missing
        python = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            .contains { FileManager.default.isExecutableFile(atPath: $0) } ? .ok : .missing
        let env = SetupModel.readEnv()
        canvasURL = env["CANVAS_URL"] ?? canvasURL
        if let t = env["CANVAS_TOKEN"], !t.isEmpty, !t.contains("paste-your") { canvasToken = t }
        canvas = Settings.availableSubjects().isEmpty ? (canvasToken.isEmpty ? .missing : .working("saved, not synced yet")) : .ok
        microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? .ok : .missing
        accessibility = EventTap.isTrusted(prompt: false) ? .ok : .missing
        calendar = EKEventStore.authorizationStatus(for: .event) == .fullAccess ? .ok : .missing
    }

    // MARK: Fixes

    func installWhisper() {
        guard let brew else {
            whisper = .failed("Homebrew not found — install it from brew.sh, then click again")
            return
        }
        whisper = .working("installing whisper.cpp (1-3 min)…")
        DispatchQueue.global().async { [brew] in
            let result = try? Shell.run(brew, ["install", "whisper-cpp"])
            DispatchQueue.main.async {
                if result?.status == 0 { self.refresh() } else { self.whisper = .failed(String(result?.stderr.suffix(200) ?? "brew failed")) }
            }
        }
    }

    func downloadModel() {
        let settings = Settings.load()
        let dest = settings.whisperModelFile
        let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(dest.lastPathComponent)")!
        model = .working("downloading \(dest.lastPathComponent)…")
        try? FileManager.default.createDirectory(at: Paths.models, withIntermediateDirectories: true)
        let delegate = DownloadProgress { [weak self] fraction in
            DispatchQueue.main.async { self?.model = .working(String(format: "downloading… %.0f%%", fraction * 100)) }
        } finished: { [weak self] tmp, error in
            DispatchQueue.main.async {
                if let tmp {
                    try? FileManager.default.removeItem(at: dest)
                    do { try FileManager.default.moveItem(at: tmp, to: dest); self?.refresh() }
                    catch { self?.model = .failed(error.localizedDescription) }
                } else {
                    self?.model = .failed(error?.localizedDescription ?? "download failed")
                }
            }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        session.downloadTask(with: url).resume()
    }

    func saveProvider() {
        var settings = Settings.load()
        settings.aiProvider = provider
        settings.save()
        refresh()
    }

    func testAI() {
        ai = .working("asking the AI to say hello…")
        let settings = Settings.load()
        Pipeline().run(.clean("Reply with exactly: DictateBar is ready."), settings: settings) { [weak self] result in
            switch result {
            case .success: self?.ai = .ok
            case .failure(let e): self?.ai = .failed(e.localizedDescription)
            }
        }
    }

    func saveCanvas() {
        let url = canvasURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let token = canvasToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard url.hasPrefix("http"), !token.isEmpty else {
            canvas = .failed("Enter your school's Canvas address (https://…instructure.com) and a token")
            return
        }
        let text = "CANVAS_URL=\(url)\nCANVAS_TOKEN=\(token)\n"
        do {
            try text.write(to: Paths.envFile, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.envFile.path)
            canvas = .working("syncing your courses…")
            runCanvasSync?()
        } catch {
            canvas = .failed(error.localizedDescription)
        }
    }

    func requestMicrophone() {
        Recorder.requestPermission { [weak self] _ in self?.refresh() }
    }

    func requestAccessibility() {
        _ = EventTap.isTrusted(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func requestCalendar() {
        EKEventStore().requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    static func readEnv() -> [String: String] {
        guard let text = try? String(contentsOf: Paths.envFile, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].hasPrefix("#") { out[parts[0]] = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
        }
        return out
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate {
    let progress: (Double) -> Void
    let finished: (URL?, Error?) -> Void
    init(progress: @escaping (Double) -> Void, finished: @escaping (URL?, Error?) -> Void) {
        self.progress = progress
        self.finished = finished
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Must move synchronously before the temp file disappears.
        let keep = FileManager.default.temporaryDirectory.appendingPathComponent("dictatebar-model-\(UUID().uuidString)")
        try? FileManager.default.moveItem(at: location, to: keep)
        finished(keep, nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finished(nil, error) }
    }
}

// MARK: - Window

final class SetupWindowController {
    private var window: NSWindow?
    let model = SetupModel()

    func show() {
        model.refresh()
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SetupView(model: model)))
            w.title = "Set up DictateBar"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 560, height: 640))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SetupView: View {
    @ObservedObject var model: SetupModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to DictateBar").font(.title2.bold())
                    Text("Speak or paste a request, get text to type — shown in your menu bar, following along as you type. Three things are required; the rest can wait.")
                        .foregroundStyle(.secondary)
                }

                section("1. Speech recognition (whisper.cpp)", state: model.whisper,
                        help: "Runs on your Mac; nothing is uploaded.") {
                    Button("Install with Homebrew") { model.installWhisper() }
                }
                section("2. Speech model (~150 MB)", state: model.model,
                        help: "Downloaded once from the whisper.cpp project.") {
                    Button("Download") { model.downloadModel() }
                }
                section("3. AI for cleanup, notes and grading", state: model.ai,
                        help: "Uses an account you already have — no API key.") {
                    Picker("", selection: $model.provider) {
                        Text("Codex (ChatGPT account)").tag(Settings.Provider.codex)
                        Text("Claude (Claude account)").tag(Settings.Provider.claude)
                    }.labelsHidden().frame(width: 220)
                    .onChange(of: model.provider) { _, _ in model.saveProvider() }
                    Button("Test") { model.testAI() }
                }
                if model.ai == .missing {
                    Text(model.provider == .codex
                         ? "Install the Codex app (or `npm i -g @openai/codex`) and sign in with your ChatGPT account, then click Test."
                         : "Install Claude Code (claude.ai/code) and run `claude auth login` in Terminal, then click Test.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Divider()

                section("Canvas (optional, recommended)", state: model.canvas,
                        help: "Lets the AI read your assignments, rubrics, modules and readings. Canvas → Account → Settings → New Access Token.") {
                    EmptyView()
                }
                VStack(spacing: 6) {
                    TextField("https://yourschool.instructure.com", text: $model.canvasURL).textFieldStyle(.roundedBorder)
                    SecureField("Access token", text: $model.canvasToken).textFieldStyle(.roundedBorder)
                    HStack {
                        Spacer()
                        Button("Save & sync courses") { model.saveCanvas() }.disabled(model.python != .ok)
                    }
                    if model.python != .ok {
                        Text("Needs python3 — run `xcode-select --install` in Terminal.").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Divider()

                section("Microphone", state: model.microphone, help: "To record.") { Button("Allow") { model.requestMicrophone() } }
                section("Accessibility", state: model.accessibility,
                        help: "For hotkeys and following your typing. Turn on DictateBar in the list that opens.") {
                    Button("Open settings") { model.requestAccessibility() }
                }
                section("Calendar (optional)", state: model.calendar, help: "Due dates and class sessions in a DictateBar calendar.") {
                    Button("Allow") { model.requestCalendar() }
                }

                HStack {
                    Button("Re-check") { model.refresh() }
                    Spacer()
                    Text(model.essentialsDone ? "Ready — press Option+R to record." : "Finish steps 1–3 to start.")
                        .foregroundStyle(model.essentialsDone ? .green : .secondary)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 560, minHeight: 640)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, state: SetupModel.State, help: String, @ViewBuilder action: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(icon(for: state)).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail(for: state) ?? help).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if state != .ok { action() }
        }
    }

    private func icon(for state: SetupModel.State) -> String {
        switch state {
        case .ok: return "✅"
        case .missing, .unknown: return "⬜️"
        case .working: return "⏳"
        case .failed: return "❌"
        }
    }

    private func detail(for state: SetupModel.State) -> String? {
        switch state {
        case .working(let s): return s
        case .failed(let s): return s
        default: return nil
        }
    }
}
