import AppKit
import SwiftUI

// MARK: - Dashboard

/// The Canvas overview: grades across the top, then missing work, what's due,
/// and what has come back graded.
struct CanvasDashboardView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if state.canvas.assignments.isEmpty {
                    EmptyCanvasNotice(state: state)
                } else {
                    if !state.canvas.hasSubmissionData { StaleSyncNotice(state: state) }
                    GradeStrip(grades: state.canvas.grades, board: state.canvas)

                    AssignmentSection(title: "Missing and overdue", systemImage: "exclamationmark.triangle.fill",
                                      tint: .red, items: state.canvas.missing,
                                      empty: "Nothing missing. ")
                    AssignmentSection(title: "Due this week", systemImage: "calendar",
                                      tint: .orange, items: state.canvas.dueSoon,
                                      empty: "Nothing due in the next seven days.")
                    AssignmentSection(title: "Recently graded", systemImage: "checkmark.seal.fill",
                                      tint: .green, items: Array(state.canvas.graded.prefix(8)),
                                      empty: "No grades posted yet.")
                    AssignmentSection(title: "Turned in, not graded", systemImage: "paperplane",
                                      tint: .blue, items: Array(state.canvas.turnedIn.prefix(8)),
                                      empty: "Nothing waiting on a grade.")
                }
            }
            .padding(20)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Canvas").font(.largeTitle.bold())
            Spacer()
            Text(state.lastSync).font(.caption).foregroundStyle(.secondary)
            Button("Sync now") { state.actions.syncCanvas() }
        }
    }
}

/// Running grade per course.
private struct GradeStrip: View {
    let grades: [CourseGrade]
    let board: CanvasBoard

    var body: some View {
        if grades.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(grades) { g in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(CourseName.short(g.display ?? g.course))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text(g.scoreText).font(.title3.bold())
                        }
                        .frame(width: 130, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.10)))
                    }
                }
            }
        }
    }
}

/// One titled block of assignment rows.
private struct AssignmentSection: View {
    let title: String
    let systemImage: String
    let tint: Color
    let items: [CanvasAssignment]
    let empty: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                if items.isEmpty {
                    Text(empty).font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, a in
                        if index > 0 { Divider() }
                        AssignmentRow(assignment: a)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label {
                HStack(spacing: 6) {
                    Text(title)
                    if !items.isEmpty {
                        Text("\(items.count)")
                            .font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(tint.opacity(0.20)))
                    }
                }
            } icon: {
                Image(systemName: systemImage).foregroundStyle(tint)
            }
        }
    }
}

private struct AssignmentRow: View {
    let assignment: CanvasAssignment

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(assignment.name).lineLimit(1)
                Text(CourseName.short(assignment.course))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let score = assignment.scoreText {
                Text(score).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(CanvasBoard.relativeDue(assignment.dueDate))
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 78, alignment: .trailing)
            StatusPill(status: assignment.status)
            if let link = assignment.url, let url = URL(string: link) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open in Canvas")
            }
        }
        .padding(.vertical, 6)
    }
}

private struct StatusPill: View {
    let status: CanvasAssignment.Status

    var body: some View {
        Text(status.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
            .frame(width: 74)
    }

    private var color: Color {
        switch status {
        case .graded: return .green
        case .submitted: return .blue
        case .missing, .overdue: return .red
        case .due: return .orange
        case .noDueDate: return .secondary
        }
    }
}

// MARK: - Assignments

/// Every assignment, filterable by course and state.
struct CanvasAssignmentsView: View {
    @ObservedObject var state: AppState
    @State private var course = "All courses"
    @State private var onlyOpen = false
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Assignments").font(.largeTitle.bold())
                Spacer()
                Toggle("Only not turned in", isOn: $onlyOpen).toggleStyle(.checkbox)
            }
            HStack {
                Picker("", selection: $course) {
                    Text("All courses").tag("All courses")
                    ForEach(state.canvas.courses, id: \.self) { Text(CourseName.short($0)).tag($0) }
                }
                .labelsHidden().frame(width: 260)
                TextField("Search", text: $search).textFieldStyle(.roundedBorder).frame(width: 220)
                Spacer()
                Text("\(filtered.count) of \(state.canvas.assignments.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if state.canvas.assignments.isEmpty {
                EmptyCanvasNotice(state: state)
                Spacer()
            } else {
                List(filtered) { a in
                    AssignmentRow(assignment: a)
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
    }

    private var filtered: [CanvasAssignment] {
        state.canvas.assignments
            .filter { course == "All courses" || $0.course == course }
            .filter { !onlyOpen || ($0.status != .graded && $0.status != .submitted) }
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }
}

// MARK: - Courses

/// One course at a time: its grade, its assignments, and what was said in class.
struct CanvasCoursesView: View {
    @ObservedObject var state: AppState
    @State private var selected = ""

    var body: some View {
        HStack(spacing: 0) {
            List(state.canvas.courses, id: \.self, selection: Binding(
                get: { selected.isEmpty ? state.canvas.courses.first ?? "" : selected },
                set: { selected = $0 ?? "" })) { course in
                VStack(alignment: .leading, spacing: 2) {
                    Text(CourseName.short(course)).lineLimit(1)
                    if let g = state.canvas.grade(for: course), g.score != nil {
                        Text(g.scoreText).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(course)
            }
            .frame(width: 220)

            Divider()

            if let course = currentCourse {
                detail(for: course)
            } else {
                VStack { EmptyCanvasNotice(state: state) }.padding(20)
            }
        }
    }

    private var currentCourse: String? {
        let c = selected.isEmpty ? state.canvas.courses.first : selected
        return (c?.isEmpty ?? true) ? nil : c
    }

    private func detail(for course: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text(CourseName.short(course)).font(.title2.bold())
                    Spacer()
                    if let g = state.canvas.grade(for: course) {
                        Text(g.scoreText).font(.title3.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }

                let items = state.canvas.assignments(in: course)
                GroupBox("Assignments (\(items.count))") {
                    VStack(alignment: .leading, spacing: 0) {
                        if items.isEmpty {
                            Text("No assignments synced for this course.")
                                .font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
                        } else {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, a in
                                if index > 0 { Divider() }
                                AssignmentRow(assignment: a)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let said = fromClass(course), !said.isEmpty {
                    GroupBox("Said in class about assignments") {
                        Text(said).font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                HStack {
                    Button("Open course folder") {
                        NSWorkspace.shared.open(Paths.library.appendingPathComponent("canvas/\(course)"))
                    }
                    Spacer()
                }
            }
            .padding(20)
        }
    }

    private func fromClass(_ course: String) -> String? {
        let url = Paths.library.appendingPathComponent("canvas/\(course)/from_class.md")
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

// MARK: - Shared pieces

/// Trims "ENGLISH 10 - 1001 - Jacobson" down to something a column can hold.
enum CourseName {
    static func short(_ name: String) -> String {
        let parts = name.components(separatedBy: " - ")
        guard parts.count >= 2 else { return name }
        let subject = parts[0].trimmingCharacters(in: .whitespaces)
        let teacher = parts.last?.trimmingCharacters(in: .whitespaces) ?? ""
        return teacher.isEmpty ? subject : "\(subject) · \(teacher)"
    }
}

private struct EmptyCanvasNotice: View {
    @ObservedObject var state: AppState

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("No Canvas data yet").font(.headline)
                Text("Add CANVAS_URL and CANVAS_TOKEN to your .env, then sync. "
                     + "Everything here is read from your own Canvas account.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Sync Canvas now") { state.actions.syncCanvas() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The library predates the submission include, so status and grades are unknown.
private struct StaleSyncNotice: View {
    @ObservedObject var state: AppState

    var body: some View {
        GroupBox {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync again to see grades and missing work").font(.callout.bold())
                    Text("This library was synced before DictateBar collected submission status.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sync now") { state.actions.syncCanvas() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
