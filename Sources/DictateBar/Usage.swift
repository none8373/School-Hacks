import Foundation

/// Per-day token/run counts for each AI provider, kept in output/usage.json.
struct Usage: Codable {
    struct Bucket: Codable { var tokens = 0; var runs = 0 }
    var days: [String: [String: Bucket]] = [:]

    private static let url = Paths.output.appendingPathComponent("usage.json")

    static func load() -> Usage {
        guard let data = try? Data(contentsOf: url), let u = try? JSONDecoder().decode(Usage.self, from: data) else { return Usage() }
        return u
    }

    static func record(provider: String, tokens: Int) {
        var usage = load()
        var day = usage.days[today()] ?? [:]
        var bucket = day[provider] ?? Bucket()
        bucket.tokens += tokens
        bucket.runs += 1
        day[provider] = bucket
        usage.days[today()] = day
        if let data = try? JSONEncoder().encode(usage) { try? data.write(to: url) }
    }

    /// "codex 12.3k tok / 5 runs today · 40.1k / 18 this week"
    static func summary(provider: String) -> String {
        let usage = load()
        let todayBucket = usage.days[today()]?[provider] ?? Bucket()
        var week = Bucket()
        for offset in 0..<7 {
            let key = dayKey(Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date())
            if let b = usage.days[key]?[provider] { week.tokens += b.tokens; week.runs += b.runs }
        }
        return "\(provider): \(short(todayBucket.tokens)) tok / \(todayBucket.runs) runs today · \(short(week.tokens)) / \(week.runs) this week"
    }

    private static func short(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }

    private static func today() -> String { dayKey(Date()) }

    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
