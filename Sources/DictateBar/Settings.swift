import Foundation

/// User-editable options, stored in config.json next to the app's data.
struct Settings: Codable, Equatable {
    enum Modifier: String, Codable {
        case option
        case controlOption = "control+option"
    }

    enum Provider: String, Codable {
        case codex, claude
    }

    var hotkeyModifier: Modifier = .option
    /// Folder name under library/canvas/ for the class you're working on ("" = let the AI infer).
    var subject: String = ""
    /// e.g. "10th grade" — used when grading and writing.
    var gradeLevel: String = ""
    /// Which AI cleans up the transcript: "codex" (ChatGPT subscription) or "claude".
    var aiProvider: Provider = .codex
    var whisperModel: String = "base.en"
    var claudeModel: String = "sonnet"
    /// 0 = fill whatever menu bar space is left on your screen.
    var lineChars: Int = 0
    /// Let the line cover the front app's menus (File, Edit…) so it can span the bar.
    /// Hide the line (Option+H) to get the menus back.
    var coverAppMenus: Bool = true
    var capsLockAutoType: Bool = true
    var launchAtLogin: Bool = false
    var setupShown: Bool = false
    var appearance = Appearance()
    var briefEnabled: Bool = true
    var briefHour: Int = 7
    var briefMinute: Int = 0
    var classAlerts: Bool = true
    var alertMinutes: Int = 5
    /// When recording a class, use whatever the schedule says you're in right now.
    var subjectFromSchedule: Bool = true
    var syncHours: Double = 4
    var whisperPath: String = "/opt/homebrew/bin/whisper-cli"
    var claudePath: String = "~/.local/bin/claude"
    /// Empty = Codex's own default model from ~/.codex/config.toml.
    var codexModel: String = ""
    var codexPath: String = "~/.codex/plugins/.plugin-appserver/codex"

    /// Course folders produced by the Canvas sync, for the subject picker.
    static func availableSubjects() -> [String] {
        let canvas = Paths.library.appendingPathComponent("canvas")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: canvas.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted()
    }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: Paths.config),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            let defaults = Settings()
            defaults.save()
            return defaults
        }
        return settings
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) {
            try? data.write(to: Paths.config)
        }
    }

    var whisperModelFile: URL {
        Paths.models.appendingPathComponent("ggml-\(whisperModel).bin")
    }

    var resolvedWhisperPath: String { Settings.expand(whisperPath) }
    var resolvedClaudePath: String { Settings.expand(claudePath) }
    var resolvedCodexPath: String {
        let bundled = Settings.expand(codexPath)
        if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", Settings.expand("~/.local/bin")] {
            let candidate = dir + "/codex"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return bundled
    }

    private static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
