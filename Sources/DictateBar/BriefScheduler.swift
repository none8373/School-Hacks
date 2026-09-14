import Foundation

/// Runs the morning brief once a day at the configured time (or as soon as the Mac
/// wakes up after it, if it was asleep).
final class BriefScheduler {
    var onDue: (() -> Void)?
    private var timer: Timer?
    private var enabled = true
    private var hour = 7
    private var minute = 0

    func configure(enabled: Bool, hour: Int, minute: Int) {
        self.enabled = enabled
        self.hour = hour
        self.minute = minute
        timer?.invalidate()
        guard enabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.check() }
        check()
    }

    static func todayURL() -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return Paths.briefs.appendingPathComponent("\(f.string(from: Date())).md")
    }

    private func check() {
        guard enabled, !FileManager.default.fileExists(atPath: BriefScheduler.todayURL().path) else { return }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        // Only fire between the set time and noon; after that, wait for tomorrow.
        if nowMinutes >= hour * 60 + minute, nowMinutes < 12 * 60 {
            onDue?()
        }
    }
}
