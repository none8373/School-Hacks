import Foundation

/// Runs one AI job (clean a transcript, write notes, grade a document) and
/// writes the result to output/current.md. Recording adds a whisper step first.
final class Pipeline {
    enum Mode {
        case clean(String)   // transcript or pasted text
        case notes(String)   // optional extra request text
        case grade(String)   // the document to grade
        case brief           // the morning brief across all classes

        var label: String {
            switch self {
            case .clean: return "clean"
            case .notes: return "notes"
            case .grade: return "grade"
            case .brief: return "brief"
            }
        }

        var promptFile: URL {
            switch self {
            case .clean: return Paths.cleanPrompt
            case .notes: return Paths.notesPrompt
            case .grade: return Paths.gradePrompt
            case .brief: return Paths.briefPrompt
            }
        }

        var input: String {
            switch self {
            case .clean(let text): return "TRANSCRIPT:\n\n" + text
            case .notes(let extra): return extra.isEmpty ? "Produce the notes for the current assignment now." : "REQUEST:\n\n" + extra
            case .grade(let doc): return "STUDENT DOCUMENT:\n\n" + doc
            case .brief: return "Produce today's morning brief now."
            }
        }

        /// Briefs are also kept by date so past mornings stay readable.
        var archiveURL: URL? {
            if case .brief = self {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                return Paths.briefs.appendingPathComponent("\(f.string(from: Date())).md")
            }
            return nil
        }
    }

    enum PipelineError: LocalizedError {
        case missingTool(String)
        case missingModel(URL)
        case toolFailed(String, String)
        case nothingHeard
        case emptyResult
        case noSubject

        var errorDescription: String? {
            switch self {
            case .missingTool(let path): return "Not found: \(path)"
            case .missingModel(let url): return "Whisper model missing. Run scripts/setup.sh (\(url.lastPathComponent))"
            case .toolFailed(let tool, let detail): return "\(tool) failed: \(detail)"
            case .nothingHeard: return "Nothing to work with (empty recording or clipboard)"
            case .emptyResult: return "The AI returned no text"
            case .noSubject: return "Pick a subject in Settings first (needs a Canvas sync)"
            }
        }
    }

    struct ClassResult {
        let subject: String
        let notes: String
        let summary: String
        let notesURL: URL
        let suggestions: [Suggestion]
    }

    private let queue = DispatchQueue(label: "dictatebar.pipeline")

    /// A whole recorded class: transcribe, write organized notes, pull out tasks.
    func runClass(wav: URL, startedAt: Date, settings: Settings, completion: @escaping (Result<ClassResult, Error>) -> Void) {
        queue.async {
            let started = Date()
            do {
                let subject = settings.subject.isEmpty ? "General" : settings.subject
                let folder = Paths.classes.appendingPathComponent(subject)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let stampFormatter = DateFormatter(); stampFormatter.dateFormat = "yyyy-MM-dd_HH-mm"
                let stamp = stampFormatter.string(from: startedAt)

                let transcript = try self.transcribe(wav, settings: settings)
                try transcript.write(to: folder.appendingPathComponent("\(stamp).transcript.txt"), atomically: true, encoding: .utf8)

                let instructions = try self.loadInstructions(promptFile: Paths.classPrompt, settings: settings)
                let raw = try self.callAI(instructions: instructions, input: "TRANSCRIPT:\n\n" + transcript, settings: settings)
                let (notes, suggestions) = Pipeline.parseClassOutput(raw, subject: subject)

                let notesURL = folder.appendingPathComponent("\(stamp).notes.md")
                try notes.write(to: notesURL, atomically: true, encoding: .utf8)
                self.appendToIndex("- classes/\(subject)/\(stamp).notes.md")
                self.appendAssignmentDetails(suggestions, subject: settings.subject, date: stamp)
                try self.writeOutput(notes)

                let summary = notes.split(separator: "\n").first { $0.hasPrefix("Summary:") }.map(String.init) ?? ""
                History.record(mode: "class", provider: settings.aiProvider.rawValue, input: "\(transcript.count) chars of transcript",
                               output: notes, error: nil, seconds: Date().timeIntervalSince(started))
                let result = ClassResult(subject: subject, notes: notes, summary: summary, notesURL: notesURL, suggestions: suggestions)
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                History.record(mode: "class", provider: settings.aiProvider.rawValue, input: wav.lastPathComponent,
                               output: nil, error: error.localizedDescription, seconds: Date().timeIntervalSince(started))
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Splits the class output into the notes text and the JSON task list.
    static func parseClassOutput(_ raw: String, subject: String) -> (String, [Suggestion]) {
        let marker = "===SUGGESTIONS==="
        var notes = raw
        var suggestions: [Suggestion] = []
        if let range = raw.range(of: marker) {
            notes = String(raw[..<range.lowerBound])
            let jsonPart = String(raw[range.upperBound...])
            if let open = jsonPart.firstIndex(of: "["), let close = jsonPart.lastIndex(of: "]") {
                struct Item: Decodable { var title: String; var details: String?; var due: String?; var canvasAssignment: String?; var kind: String? }
                let data = Data(jsonPart[open...close].utf8)
                let items = (try? JSONDecoder().decode([Item].self, from: data)) ?? []
                let now = ISO8601DateFormatter().string(from: Date())
                suggestions = items.map {
                    Suggestion(id: "class-\(UUID().uuidString.prefix(8))", subject: subject, title: $0.title, details: $0.details ?? "",
                               due: $0.due == "null" ? nil : $0.due, canvasAssignment: $0.canvasAssignment, kind: $0.kind ?? "homework",
                               source: "class", createdAt: now)
                }
            }
        }
        if notes.hasPrefix("NOTES") { notes = String(notes.dropFirst(5)) }
        return (notes.trimmingCharacters(in: .whitespacesAndNewlines), suggestions)
    }

    private func appendToIndex(_ line: String) {
        let index = Paths.library.appendingPathComponent("INDEX.md")
        var text = (try? String(contentsOf: index, encoding: .utf8)) ?? "# Library index\n"
        text = text.replacingOccurrences(of: "(none yet - record a class with Option+C)\n", with: "")
        text += line + "\n"
        try? text.write(to: index, atomically: true, encoding: .utf8)
    }

    /// Things the teacher said about a Canvas assignment go next to that assignment.
    private func appendAssignmentDetails(_ suggestions: [Suggestion], subject: String, date: String) {
        guard !subject.isEmpty else { return }
        let file = Paths.library.appendingPathComponent("canvas/\(subject)/from_class.md")
        var text = (try? String(contentsOf: file, encoding: .utf8)) ?? "# Said in class about assignments\n\n"
        var added = false
        for s in suggestions {
            let target = s.canvasAssignment ?? s.title
            text += "- \(date) — \(target): \(s.details)" + (s.due.map { " (due \($0))" } ?? "") + "\n"
            added = true
        }
        if added { try? text.write(to: file, atomically: true, encoding: .utf8) }
    }

    /// Recording: transcribe, then clean.
    func run(wav: URL, settings: Settings, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            do {
                let transcript = try self.transcribe(wav, settings: settings)
                try transcript.write(to: wav.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
                self.execute(.clean(transcript), settings: settings, completion: completion)
            } catch {
                History.record(mode: "transcribe", provider: "whisper", input: wav.lastPathComponent,
                               output: nil, error: error.localizedDescription, seconds: 0)
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func run(_ mode: Mode, settings: Settings, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async { self.execute(mode, settings: settings, completion: completion) }
    }

    // MARK: Core

    private func execute(_ mode: Mode, settings: Settings, completion: @escaping (Result<String, Error>) -> Void) {
        let started = Date()
        let provider = settings.aiProvider.rawValue
        do {
            if case .clean(let text) = mode, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw PipelineError.nothingHeard
            }
            if case .grade(let doc) = mode, doc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw PipelineError.nothingHeard
            }
            if case .notes = mode, settings.subject.isEmpty { throw PipelineError.noSubject }

            let instructions = try loadInstructions(promptFile: mode.promptFile, settings: settings)
            let output = try callAI(instructions: instructions, input: mode.input, settings: settings)
            try writeOutput(output)
            if let archive = mode.archiveURL { try? output.write(to: archive, atomically: true, encoding: .utf8) }
            History.record(mode: mode.label, provider: provider, input: mode.input, output: output,
                           error: nil, seconds: Date().timeIntervalSince(started))
            DispatchQueue.main.async { completion(.success(output)) }
        } catch {
            History.record(mode: mode.label, provider: provider, input: mode.input, output: nil,
                           error: error.localizedDescription, seconds: Date().timeIntervalSince(started))
            try? "\(Date())\n\(error.localizedDescription)\n".write(
                to: Paths.output.appendingPathComponent("last_error.log"), atomically: true, encoding: .utf8)
            DispatchQueue.main.async { completion(.failure(error)) }
        }
    }

    /// Runs the chosen provider and records token usage.
    private func callAI(instructions: String, input: String, settings: Settings) throws -> String {
        let (text, tokens): (String, Int)
        switch settings.aiProvider {
        case .codex: (text, tokens) = try runCodex(instructions: instructions, input: input, settings: settings)
        case .claude: (text, tokens) = try runClaude(instructions: instructions, input: input, settings: settings)
        }
        Usage.record(provider: settings.aiProvider.rawValue, tokens: tokens)
        return text
    }

    /// Prompt file plus a CONTEXT block: date, subject, grade level.
    private func loadInstructions(promptFile: URL, settings: Settings) throws -> String {
        let prompt = (try? String(contentsOf: promptFile, encoding: .utf8)) ?? ""
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        var context = "\n\nCONTEXT\nToday: \(f.string(from: Date()))\n"
        context += "Subject folder: " + (settings.subject.isEmpty ? "(none selected - infer from the request)" : "canvas/\(settings.subject)") + "\n"
        context += "Grade level: " + (settings.gradeLevel.isEmpty ? "(unknown - infer from the course name)" : settings.gradeLevel) + "\n"
        context += "Library root is the current directory; INDEX.md lists everything. classes/<subject>/ holds notes and transcripts of recorded classes; canvas/<subject>/from_class.md holds what the teacher said about assignments.\n"
        return prompt + context
    }

    // MARK: Whisper

    private func transcribe(_ wav: URL, settings: Settings) throws -> String {
        let whisper = settings.resolvedWhisperPath
        guard FileManager.default.isExecutableFile(atPath: whisper) else { throw PipelineError.missingTool(whisper) }
        let model = settings.whisperModelFile
        guard FileManager.default.fileExists(atPath: model.path) else { throw PipelineError.missingModel(model) }

        let base = wav.deletingPathExtension().path + ".whisper"
        let result = try Shell.run(whisper, [
            "-m", model.path, "-f", wav.path, "-nt", "-np", "-otxt", "-of", base,
        ])
        guard result.status == 0 else { throw PipelineError.toolFailed("whisper", lastLine(result.stderr)) }
        let text = (try? String(contentsOfFile: base + ".txt", encoding: .utf8)) ?? result.stdout
        try? FileManager.default.removeItem(atPath: base + ".txt")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "[BLANK_AUDIO]" else { throw PipelineError.nothingHeard }
        return trimmed
    }

    // MARK: AI providers

    /// Codex CLI (OpenAI) — signed in with the ChatGPT account via the Codex app.
    private func runCodex(instructions: String, input: String, settings: Settings) throws -> (String, Int) {
        let codex = settings.resolvedCodexPath
        guard FileManager.default.isExecutableFile(atPath: codex) else { throw PipelineError.missingTool(codex) }
        let outFile = FileManager.default.temporaryDirectory.appendingPathComponent("dictatebar-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outFile) }

        var args = ["exec", "--sandbox", "read-only", "--cd", Paths.library.path, "--skip-git-repo-check",
                    "--ephemeral", "--color", "never", "--output-last-message", outFile.path]
        if !settings.codexModel.isEmpty { args += ["--model", settings.codexModel] }
        args.append(instructions)

        let result = try Shell.run(codex, args, cwd: Paths.library, stdin: input)
        guard result.status == 0 else {
            let detail = result.stderr
            if detail.contains("login") || detail.contains("auth") {
                throw PipelineError.toolFailed("codex", "not signed in. Open the Codex app and log in, or run: codex login")
            }
            throw PipelineError.toolFailed("codex", lastLine(detail))
        }
        let text = ((try? String(contentsOf: outFile, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PipelineError.emptyResult }
        // Codex prints "tokens used\n4,301" at the end of stderr.
        var tokens = 0
        if let range = result.stderr.range(of: "tokens used", options: .backwards) {
            let tail = result.stderr[range.upperBound...].replacingOccurrences(of: ",", with: "")
            tokens = Int(tail.trimmingCharacters(in: .whitespacesAndNewlines).prefix { $0.isNumber }) ?? 0
        }
        return (text, tokens)
    }

    /// Claude Code CLI — signed in with the Claude subscription (`claude auth login`).
    private func runClaude(instructions: String, input: String, settings: Settings) throws -> (String, Int) {
        let claude = settings.resolvedClaudePath
        guard FileManager.default.isExecutableFile(atPath: claude) else { throw PipelineError.missingTool(claude) }

        let result = try Shell.run(claude, [
            "-p",
            "--model", settings.claudeModel,
            "--output-format", "json",
            "--allowedTools", "Read", "Grep", "Glob",
            "--append-system-prompt", instructions,
        ], cwd: Paths.library, stdin: input)
        guard result.status == 0 else {
            let detail = result.stderr + result.stdout
            if detail.contains("authenticate") || detail.contains("log in") || detail.contains("login") {
                throw PipelineError.toolFailed("claude", "not signed in. Run: claude auth login")
            }
            throw PipelineError.toolFailed("claude", lastLine(detail))
        }
        struct Reply: Decodable {
            struct UsageInfo: Decodable { var input_tokens: Int?; var output_tokens: Int? }
            var result: String?
            var usage: UsageInfo?
        }
        let reply = try? JSONDecoder().decode(Reply.self, from: Data(result.stdout.utf8))
        let text = (reply?.result ?? result.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PipelineError.emptyResult }
        let tokens = (reply?.usage?.input_tokens ?? 0) + (reply?.usage?.output_tokens ?? 0)
        return (text, tokens)
    }

    // MARK: Output

    private func writeOutput(_ text: String) throws {
        if let previous = try? String(contentsOf: Paths.current, encoding: .utf8), !previous.isEmpty {
            let stamp = Pipeline.timestamp()
            try? previous.write(to: Paths.history.appendingPathComponent("\(stamp).md"), atomically: true, encoding: .utf8)
        }
        try text.write(to: Paths.current, atomically: true, encoding: .utf8)
    }

    static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: Date())
    }

    private func lastLine(_ s: String) -> String {
        s.split(separator: "\n").last.map(String.init) ?? "exit code non-zero"
    }
}
