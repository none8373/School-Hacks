import Foundation

/// Everything the Canvas pages show, grouped the way a student needs it:
/// what is missing, what is due next, what came back graded.
struct CanvasBoard: Equatable {
    var assignments: [CanvasAssignment] = []
    var grades: [CourseGrade] = []

    static let empty = CanvasBoard()

    static func load() -> CanvasBoard {
        CanvasBoard(assignments: CanvasAssignment.loadAll(), grades: CourseGrade.loadAll())
    }

    /// False when the library was written by a sync that predates the submission
    /// include — the pages say so instead of pretending nothing is missing.
    var hasSubmissionData: Bool { assignments.contains { $0.hasSubmissionData } }

    var courses: [String] { Array(Set(assignments.map(\.course))).sorted() }

    /// Not turned in and past due. The first thing to show.
    var missing: [CanvasAssignment] {
        assignments.filter { $0.status == .missing || $0.status == .overdue }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    /// Due from now to the end of the coming week, still not turned in.
    var dueSoon: [CanvasAssignment] {
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return assignments
            .filter { $0.status == .due }
            .filter { guard let d = $0.dueDate else { return false }; return d <= horizon }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    /// Due later than a week out, still open.
    var upcoming: [CanvasAssignment] {
        let horizon = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return assignments
            .filter { $0.status == .due }
            .filter { guard let d = $0.dueDate else { return false }; return d > horizon }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var graded: [CanvasAssignment] {
        assignments.filter { $0.status == .graded }
            .sorted { ($0.dueDate ?? .distantPast) > ($1.dueDate ?? .distantPast) }
    }

    var turnedIn: [CanvasAssignment] {
        assignments.filter { $0.status == .submitted }
            .sorted { ($0.dueDate ?? .distantPast) > ($1.dueDate ?? .distantPast) }
    }

    func assignments(in course: String) -> [CanvasAssignment] {
        assignments.filter { $0.course == course }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    func grade(for course: String) -> CourseGrade? {
        grades.first { $0.course == course }
    }

    /// "Due Tuesday", "Due in 3 days", "2 days ago" — short enough for a list row.
    static func relativeDue(_ date: Date?) -> String {
        guard let date else { return "No due date" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                   to: Calendar.current.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6:
            let f = DateFormatter(); f.dateFormat = "EEEE"
            return f.string(from: date)
        case let d where d < 0:
            return d == -1 ? "Yesterday" : "\(-d) days ago"
        default:
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return f.string(from: date)
        }
    }
}
