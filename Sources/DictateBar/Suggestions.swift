import Foundation

/// A task worth doing next: from a recorded class or an upcoming Canvas assignment.
struct Suggestion: Codable, Equatable {
    var id: String
    var subject: String
    var title: String
    var details: String
    var due: String?            // YYYY-MM-DD
    var canvasAssignment: String?
    var kind: String
    var source: String          // "class" | "canvas"
    var done: Bool = false
    var createdAt: String
}

/// Keeps library/suggestions.json and the current pick.
final class SuggestionStore {
    private static let url = Paths.library.appendingPathComponent("suggestions.json")
    private(set) var items: [Suggestion] = []
    private var index = 0

    init() { load() }

    var current: Suggestion? {
        let open = openItems
        guard !open.isEmpty else { return nil }
        return open[index % open.count]
    }

    var openItems: [Suggestion] {
        items.filter { !$0.done }.sorted { ($0.due ?? "9999") < ($1.due ?? "9999") }
    }

    func next() {
        index += 1
    }

    func markCurrentDone() {
        guard let c = current, let i = items.firstIndex(where: { $0.id == c.id }) else { return }
        items[i].done = true
        save()
    }

    func toggleDone(_ s: Suggestion) {
        guard let i = items.firstIndex(where: { $0.id == s.id }) else { return }
        items[i].done.toggle()
        save()
    }

    /// Adds new items, skipping ones with the same subject + title.
    func add(_ new: [Suggestion]) {
        for s in new where !items.contains(where: { $0.subject == s.subject && $0.title.lowercased() == s.title.lowercased() }) {
            items.append(s)
        }
        save()
    }

    /// Upcoming Canvas assignments (next 14 days) become suggestions too.
    func mergeCanvas(_ assignments: [CanvasAssignment]) {
        let cutoff = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
        let f = ISO8601DateFormatter()
        var new: [Suggestion] = []
        for a in assignments {
            guard let dueString = a.due_at, let due = f.date(from: dueString), due > Date(), due < cutoff else { continue }
            let day = DateFormatter(); day.dateFormat = "yyyy-MM-dd"
            new.append(Suggestion(id: "canvas-\(a.id)", subject: a.course, title: a.name,
                                  details: "Canvas assignment, \(a.points.map { "\($0) points" } ?? "")",
                                  due: day.string(from: due), canvasAssignment: a.name, kind: "homework",
                                  source: "canvas", createdAt: f.string(from: Date())))
        }
        add(new)
    }

    private func load() {
        guard let data = try? Data(contentsOf: SuggestionStore.url),
              let list = try? JSONDecoder().decode([Suggestion].self, from: data) else { return }
        items = list
    }

    private func save() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(items) { try? data.write(to: SuggestionStore.url) }
    }
}

/// One Canvas assignment as written by sync_canvas.py into library/calendar.json.
/// Everything below `url` comes from the submission include and is optional, so a
/// calendar.json written by an older sync still decodes.
struct CanvasAssignment: Codable, Identifiable, Equatable {
    var id: Int
    var course: String
    var name: String
    var due_at: String?
    var points: Double?
    var url: String?
    var submitted_at: String?
    var score: Double?
    var grade: String?
    var state: String?          // unsubmitted | submitted | graded
    var missing: Bool?
    var late: Bool?

    /// What the dashboard shows for this row.
    enum Status: String {
        case graded = "Graded"
        case submitted = "Turned in"
        case missing = "Missing"
        case overdue = "Overdue"
        case due = "Due"
        case noDueDate = "No due date"
    }

    var dueDate: Date? { due_at.flatMap { ISO8601DateFormatter().date(from: $0) } }

    var status: Status {
        if state == "graded", score != nil { return .graded }
        if missing == true { return .missing }
        if submitted_at != nil || state == "submitted" { return .submitted }
        guard let due = dueDate else { return .noDueDate }
        return due < Date() ? .overdue : .due
    }

    /// "18/20" when graded, otherwise just the points the assignment is worth.
    var scoreText: String? {
        if let score, let points { return "\(trim(score))/\(trim(points))" }
        if let score { return trim(score) }
        if let points { return "\(trim(points)) pts" }
        return nil
    }

    /// True when the sync that produced this row included submission data.
    var hasSubmissionData: Bool { state != nil }

    private func trim(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }

    static func loadAll() -> [CanvasAssignment] {
        let url = Paths.library.appendingPathComponent("calendar.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([CanvasAssignment].self, from: data)) ?? []
    }
}

/// The running grade for one course, from library/grades.json.
struct CourseGrade: Codable, Identifiable, Equatable {
    var course: String
    var display: String?
    var teacher: String?
    var score: Double?
    var letter: String?

    var id: String { course }

    var scoreText: String {
        guard let score else { return "—" }
        let rounded = score == score.rounded() ? String(Int(score)) : String(format: "%.1f", score)
        return letter.map { "\(rounded)% (\($0))" } ?? "\(rounded)%"
    }

    static func loadAll() -> [CourseGrade] {
        let url = Paths.library.appendingPathComponent("grades.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([CourseGrade].self, from: data)) ?? []
    }
}
