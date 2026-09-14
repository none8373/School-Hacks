import EventKit
import Foundation

/// Mirrors assignments, class sessions and suggestions into a "DictateBar" calendar
/// (created in iCloud when available, so it shows up on every device).
final class CalendarSync {
    private let store = EKEventStore()
    private let calendarName = "DictateBar"

    func requestAccess(_ completion: @escaping (Bool) -> Void) {
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Push everything we know about. Safe to call repeatedly: events are keyed, not duplicated.
    func syncAll(suggestions: [Suggestion], completion: @escaping (Result<Int, Error>) -> Void) {
        requestAccess { [weak self] granted in
            guard let self else { return }
            guard granted else {
                completion(.failure(NSError(domain: "DictateBar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Calendar access denied (System Settings → Privacy → Calendars)"])))
                return
            }
            do {
                let calendar = try self.calendar()
                var count = 0
                let iso = ISO8601DateFormatter()
                for a in CanvasAssignment.loadAll() {
                    guard let dueString = a.due_at, let due = iso.date(from: dueString) else { continue }
                    let short = a.course.split(separator: "-").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? a.course
                    try self.upsert(key: "canvas-\(a.id)", title: "\(short): \(a.name)", start: due.addingTimeInterval(-3600), end: due,
                                    allDay: false, notes: a.url ?? "", calendar: calendar)
                    count += 1
                }
                let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"
                for s in suggestions where s.source == "class" && !s.done {
                    guard let dueString = s.due, let due = day.date(from: dueString) else { continue }
                    try self.upsert(key: "suggestion-\(s.id)", title: "To do: \(s.title)", start: due, end: due,
                                    allDay: true, notes: s.details, calendar: calendar)
                    count += 1
                }
                completion(.success(count))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// One event for a recorded class, with the notes summary attached.
    func addClassSession(subject: String, start: Date, end: Date, notesPath: String, summary: String) {
        requestAccess { [weak self] granted in
            guard let self, granted, let calendar = try? self.calendar() else { return }
            let key = "class-\(Int(start.timeIntervalSince1970))"
            let short = subject.split(separator: "-").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? subject
            try? self.upsert(key: key, title: "Class: \(short)", start: start, end: end, allDay: false,
                             notes: summary + "\n\nNotes: \(notesPath)", calendar: calendar)
        }
    }

    // MARK: Internals

    private func calendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == calendarName }) { return existing }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = calendarName
        let icloud = store.sources.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
        guard let source = icloud ?? store.defaultCalendarForNewEvents?.source ?? store.sources.first else {
            throw NSError(domain: "DictateBar", code: 2, userInfo: [NSLocalizedDescriptionKey: "No calendar account found"])
        }
        cal.source = source
        try store.saveCalendar(cal, commit: true)
        return cal
    }

    private func upsert(key: String, title: String, start: Date, end: Date, allDay: Bool, notes: String, calendar: EKCalendar) throws {
        let marker = "[dictatebar:\(key)]"
        let window = store.predicateForEvents(withStart: start.addingTimeInterval(-86400 * 2), end: end.addingTimeInterval(86400 * 2), calendars: [calendar])
        let event = store.events(matching: window).first { $0.notes?.contains(marker) == true } ?? EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = end
        event.isAllDay = allDay
        event.notes = notes + "\n\n" + marker
        try store.save(event, span: .thisEvent, commit: true)
    }
}
