import Foundation

/// Every file the app touches lives under one project folder.
enum Paths {
    static let root: URL = {
        if let custom = ProcessInfo.processInfo.environment["DICTATEBAR_HOME"] {
            return URL(fileURLWithPath: custom)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/DictateBar")
    }()

    static let config = root.appendingPathComponent("config.json")
    static let output = root.appendingPathComponent("output")
    static let current = output.appendingPathComponent("current.md")
    static let history = output.appendingPathComponent("history")
    static let recordings = root.appendingPathComponent("recordings")
    static let library = root.appendingPathComponent("library")
    static let lastSync = library.appendingPathComponent(".last_sync")
    /// Outside Documents on purpose: iCloud "optimize storage" evicts big files from synced folders.
    static let models = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DictateBar/models")
    /// Prompts and the sync script ship inside the .app; a source checkout next to the
    /// data folder overrides them so edits are picked up without rebuilding.
    static let resources: URL = {
        let dev = root.appendingPathComponent("prompts")
        if FileManager.default.fileExists(atPath: dev.path) { return root }
        return Bundle.main.resourceURL ?? root
    }()
    static let cleanPrompt = resources.appendingPathComponent("prompts/clean.md")
    static let notesPrompt = resources.appendingPathComponent("prompts/notes.md")
    static let gradePrompt = resources.appendingPathComponent("prompts/grade.md")
    static let classPrompt = resources.appendingPathComponent("prompts/class.md")
    static let pagePrompt = resources.appendingPathComponent("prompts/page.md")
    static let briefPrompt = resources.appendingPathComponent("prompts/brief.md")
    static let schedulePrompt = resources.appendingPathComponent("prompts/schedule.md")
    static let schoolPrompt = resources.appendingPathComponent("prompts/school.md")
    static let pdfTextScript = resources.appendingPathComponent("sync/pdf_text.py")
    static let scheduleDocs = library.appendingPathComponent("schedule")
    static let briefs = library.appendingPathComponent("briefs")
    static let envFile = root.appendingPathComponent(".env")
    /// Outside Documents for the same reason as the models: iCloud evicts files from
    /// synced folders, and an evicted package makes `import requests` time out mid-sync.
    static let venv = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DictateBar/venv")
    static let classes = library.appendingPathComponent("classes")
    static let syncScript = resources.appendingPathComponent("sync/sync_canvas.py")
    static let venvPython = venv.appendingPathComponent("bin/python")

    static func ensureFolders() {
        for dir in [output, history, recordings, library, models, classes, briefs, scheduleDocs] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
