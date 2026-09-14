import Foundation

/// The school timetable: rotating cycle days, bell periods, and which class sits in each.
struct Schedule: Codable, Equatable {
    struct Period: Codable, Equatable {
        var name: String
        var start: String   // "07:45"
        var end: String
    }
    struct Anchor: Codable, Equatable {
        var date: String    // "YYYY-MM-DD"
        var day: String     // a cycle label
    }

    var cycleLength: Int
    var cycleLabels: [String]
    var anchor: Anchor
    var periods: [Period]
    var classes: [String: [String: String]]   // cycle label -> period name -> class
    var holidays: [String]
    var notes: String?

    static let url = Paths.library.appendingPathComponent("schedule.json")

    static func load() -> Schedule? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Schedule.self, from: data)
    }

    func save() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: Schedule.url) }
    }

    // MARK: Cycle days

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    func isSchoolDay(_ date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        guard weekday != 1, weekday != 7 else { return false }
        return !holidays.contains(Schedule.dayFormatter.string(from: date))
    }

    /// Which cycle label a date falls on, counting school days from the anchor.
    func cycleLabel(for date: Date) -> String? {
        guard isSchoolDay(date), cycleLength > 0, !cycleLabels.isEmpty,
              let anchorDate = Schedule.dayFormatter.date(from: anchor.date),
              let anchorIndex = cycleLabels.firstIndex(of: anchor.day) else { return nil }
        let cal = Calendar.current
        let from = cal.startOfDay(for: anchorDate)
        let to = cal.startOfDay(for: date)
        var count = 0
        var cursor = min(from, to)
        let end = max(from, to)
        while cursor < end {
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
            if isSchoolDay(cursor) { count += 1 }
        }
        let offset = to >= from ? count : -count
        let index = ((anchorIndex + offset) % cycleLength + cycleLength) % cycleLength
        return cycleLabels.indices.contains(index) ? cycleLabels[index] : nil
    }

    /// Pin today's cycle day (the user knows better than the calendar).
    mutating func setToday(_ label: String) {
        anchor = Anchor(date: Schedule.dayFormatter.string(from: Date()), day: label)
    }

    // MARK: Today

    struct Slot: Equatable {
        var period: Period
        var className: String
        var start: Date
        var end: Date
    }

    func slots(for date: Date = Date()) -> [Slot] {
        guard let label = cycleLabel(for: date) else { return [] }
        let map = classes[label] ?? [:]
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        return periods.compactMap { p in
            guard let s = Schedule.time(p.start, on: day), let e = Schedule.time(p.end, on: day) else { return nil }
            return Slot(period: p, className: map[p.name] ?? "Free", start: s, end: e)
        }
    }

    func current(at now: Date = Date()) -> Slot? {
        slots(for: now).first { $0.start <= now && now < $0.end }
    }

    func next(after now: Date = Date()) -> Slot? {
        slots(for: now).first { $0.start > now && $0.className != "Free" }
    }

    private static func time(_ hhmm: String, on day: Date) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
    }

    /// A one-line summary for menus, prompts and the bar.
    func summary(at now: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm"
        guard let label = cycleLabel(for: now) else { return "No school today" }
        var s = "Day \(label)"
        if let c = current(at: now) { s += " · now: \(short(c.className)) until \(f.string(from: c.end))" }
        if let n = next(after: now) { s += " · next: \(short(n.className)) at \(f.string(from: n.start))" }
        else if current(at: now) == nil { s += " · no more classes today" }
        return s
    }

    /// "Chem 9:17 · 12m left" for the menu bar info line.
    func compact(at now: Date = Date()) -> String? {
        guard cycleLabel(for: now) != nil else { return nil }
        let f = DateFormatter(); f.dateFormat = "h:mm"
        var parts: [String] = []
        if let n = next(after: now) { parts.append("\(short(n.className)) \(f.string(from: n.start))") }
        if let c = current(at: now) {
            let left = Int(c.end.timeIntervalSince(now) / 60)
            parts.append("\(left)m left")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func short(_ course: String) -> String {
        course.split(separator: "-").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? course
    }
}
