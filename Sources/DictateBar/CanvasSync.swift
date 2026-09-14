import Foundation

/// Runs sync/sync_canvas.py, on demand and on a timer.
final class CanvasSync {
    private let queue = DispatchQueue(label: "dictatebar.sync")
    private var timer: Timer?
    private(set) var isRunning = false

    var onFinished: ((Result<String, Error>) -> Void)?

    struct SyncError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func schedule(everyHours hours: Double) {
        timer?.invalidate()
        guard hours > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: hours * 3600, repeats: true) { [weak self] _ in
            self?.runNow()
        }
    }

    func runNow() {
        guard !isRunning else { return }
        isRunning = true
        queue.async {
            let outcome: Result<String, Error>
            do {
                try CanvasSync.ensureVenv()
                let result = try Shell.run(Paths.venvPython.path, [Paths.syncScript.path], cwd: Paths.root,
                                           env: ["DICTATEBAR_HOME": Paths.root.path])
                if result.status == 0 {
                    outcome = .success(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let detail = result.stderr.split(separator: "\n").last.map(String.init) ?? "sync failed"
                    outcome = .failure(SyncError(message: detail))
                }
            } catch {
                outcome = .failure(error)
            }
            DispatchQueue.main.async {
                self.isRunning = false
                self.onFinished?(outcome)
            }
        }
    }

    /// First run: make a private Python environment with the two packages the sync needs.
    static func ensureVenv() throws {
        if FileManager.default.isExecutableFile(atPath: Paths.venvPython.path) { return }
        guard let python = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw SyncError(message: "python3 not found — install Xcode Command Line Tools (xcode-select --install)")
        }
        let create = try Shell.run(python, ["-m", "venv", Paths.venv.path])
        guard create.status == 0 else { throw SyncError(message: "Could not create Python environment: \(create.stderr.suffix(200))") }
        let pip = try Shell.run(Paths.venv.appendingPathComponent("bin/pip").path, ["install", "-q", "requests", "pypdf"])
        guard pip.status == 0 else { throw SyncError(message: "pip install failed: \(pip.stderr.suffix(200))") }
    }

    static func lastSyncDescription() -> String {
        guard let date = (try? FileManager.default.attributesOfItem(atPath: Paths.lastSync.path))?[.modificationDate] as? Date else {
            return "never synced"
        }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return "synced " + f.localizedString(for: date, relativeTo: Date())
    }
}
