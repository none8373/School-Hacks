import Foundation

/// What the main window shows, kept in sync by the app; plus the actions it can trigger.
final class AppState: ObservableObject {
    struct HistoryEntry: Identifiable {
        let id = UUID()
        let header: String
        let input: String
        let output: String
    }

    struct ClassNote: Identifiable {
        let id: URL
        let subject: String
        let name: String
        let text: String
    }

    @Published var currentText = ""
    @Published var statusText = "Ready"
    @Published var isRecording = false
    @Published var suggestion: Suggestion?
    @Published var suggestions: [Suggestion] = []
    @Published var usageCodex = ""
    @Published var usageClaude = ""
    @Published var history: [HistoryEntry] = []
    @Published var classNotes: [ClassNote] = []
    @Published var briefs: [ClassNote] = []      // reuse: subject = date, text = brief

    struct Actions {
        var record: () -> Void = {}
        var recordClass: () -> Void = {}
        var clipboardPrompt: () -> Void = {}
        var notes: () -> Void = {}
        var grade: () -> Void = {}
        var pasteNotes: () -> Void = {}
        var writeSuggestion: () -> Void = {}
        var nextSuggestion: () -> Void = {}
        var doneSuggestion: () -> Void = {}
        var toggleSuggestionDone: (Suggestion) -> Void = { _ in }
        var useText: (String) -> Void = { _ in }
        var syncCanvas: () -> Void = {}
        var syncCalendar: () -> Void = {}
        var openSetup: () -> Void = {}
        var applySettings: (Settings) -> Void = { _ in }
        var generateBrief: () -> Void = {}
    }
    var actions = Actions()

    func reloadFiles() {
        currentText = (try? String(contentsOf: Paths.current, encoding: .utf8)) ?? ""
        usageCodex = Usage.summary(provider: "codex")
        usageClaude = Usage.summary(provider: "claude")
        history = AppState.parseHistory()
        classNotes = AppState.loadClassNotes()
        briefs = AppState.loadBriefs()
    }

    private static func loadBriefs() -> [ClassNote] {
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.briefs, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { ClassNote(id: $0, subject: $0.deletingPathExtension().lastPathComponent, name: $0.deletingPathExtension().lastPathComponent,
                             text: (try? String(contentsOf: $0, encoding: .utf8)) ?? "") }
    }

    private static func parseHistory() -> [HistoryEntry] {
        guard let text = try? String(contentsOf: History.url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "==== ").dropFirst().reversed().prefix(200).map { block in
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
            let header = lines.first.map(String.init) ?? ""
            let rest = lines.dropFirst().joined(separator: "\n")
            let parts = rest.components(separatedBy: "-- output\n")
            let input = parts[0].replacingOccurrences(of: "-- input\n", with: "")
            let output = parts.count > 1 ? parts[1] : rest.components(separatedBy: "-- error\n").last ?? ""
            return HistoryEntry(header: header, input: input.trimmingCharacters(in: .whitespacesAndNewlines),
                                output: output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func loadClassNotes() -> [ClassNote] {
        guard let files = FileManager.default.enumerator(at: Paths.classes, includingPropertiesForKeys: nil) else { return [] }
        return files.compactMap { $0 as? URL }
            .filter { $0.lastPathComponent.hasSuffix(".notes.md") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { url in
                ClassNote(id: url, subject: url.deletingLastPathComponent().lastPathComponent,
                          name: url.lastPathComponent.replacingOccurrences(of: ".notes.md", with: ""),
                          text: (try? String(contentsOf: url, encoding: .utf8)) ?? "")
            }
    }
}
