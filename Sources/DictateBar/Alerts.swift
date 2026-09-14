import Foundation
import UserNotifications

/// "Spanish 2 in 5 minutes (Room …)" — a notification before each class.
final class ClassAlerts {
    private var timer: Timer?
    private var fired: Set<String> = []
    var minutesBefore = 5
    var enabled = true
    var schedule: Schedule?

    func start() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.check() }
    }

    private func check() {
        guard enabled, let schedule else { return }
        let now = Date()
        for slot in schedule.slots(for: now) where slot.className != "Free" {
            let lead = slot.start.addingTimeInterval(-Double(minutesBefore) * 60)
            let key = "\(slot.period.name)-\(Int(slot.start.timeIntervalSince1970))"
            if now >= lead, now < slot.start, !fired.contains(key) {
                fired.insert(key)
                let f = DateFormatter(); f.dateFormat = "h:mm"
                notify(title: "\(schedule.short(slot.className)) at \(f.string(from: slot.start))",
                       body: "\(slot.period.name) starts in \(minutesBefore) min. Press ⌥C when it begins to record the class.")
            }
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
