import Foundation

/// The text you are typing along to, plus a marker (cursor) showing where you are.
/// Matching is deliberately forgiving: the text is a guide, not a test.
final class TextGuide {
    private(set) var chars: [Character] = []
    private(set) var cursor: Int = 0

    var isEmpty: Bool { chars.isEmpty }
    var isFinished: Bool { cursor >= chars.count }

    func load(_ raw: String) {
        chars = Array(TextGuide.normalize(raw))
        cursor = 0
    }

    // MARK: Typing

    /// Advance if `typed` matches the next expected character. Returns true if it moved.
    /// A space always means "next word": however the word was spelled, the marker jumps
    /// to the start of the next word in the guide so a typo can never leave it stuck.
    @discardableResult
    func typed(_ typed: Character) -> Bool {
        guard !isFinished else { return false }
        let t = TextGuide.fold(typed)
        if t == " " {
            if chars[cursor] == " " {
                cursor += 1
                while cursor < chars.count, chars[cursor] == " " { cursor += 1 }
            } else {
                nextWord()
            }
            return true
        }
        if t == TextGuide.fold(chars[cursor]) {
            cursor += 1
            return true
        }
        // Forgive a skipped space or punctuation mark: "hello,world" still tracks "hello, world".
        let next = cursor + 1
        if next < chars.count, !chars[cursor].isLetter, !chars[cursor].isNumber,
           t == TextGuide.fold(chars[next]) {
            cursor = next + 1
            return true
        }
        return false
    }

    func backspace() {
        cursor = max(0, cursor - 1)
    }

    // MARK: Manual navigation

    func nextWord() {
        var i = cursor
        while i < chars.count, chars[i] != " " { i += 1 }
        while i < chars.count, chars[i] == " " { i += 1 }
        cursor = i
    }

    func previousWord() {
        var i = cursor
        while i > 0, chars[i - 1] == " " { i -= 1 }
        while i > 0, chars[i - 1] != " " { i -= 1 }
        cursor = i
    }

    func nextSentence() {
        var i = cursor
        while i < chars.count {
            if isSentenceEnd(i) { cursor = min(chars.count, i + 2); return }
            i += 1
        }
        cursor = chars.count
    }

    func previousSentence() {
        var i = cursor - 3
        while i >= 0 {
            if isSentenceEnd(i) { cursor = i + 2; return }
            i -= 1
        }
        cursor = 0
    }

    func moveTo(_ index: Int) {
        cursor = min(max(0, index), chars.count)
    }

    private func isSentenceEnd(_ i: Int) -> Bool {
        guard ".!?".contains(chars[i]) else { return false }
        return i + 1 >= chars.count || chars[i + 1] == " "
    }

    // MARK: Display window

    struct Window {
        var typed: String
        var current: String
        var upcoming: String
    }

    /// The slice of text to show, keeping the marker near the left so you see a little of what you typed.
    func window(chars width: Int) -> Window {
        guard !chars.isEmpty else { return Window(typed: "", current: "", upcoming: "") }
        let lead = width / 4
        var start = max(0, cursor - lead)
        start = min(start, max(0, chars.count - width))
        let end = min(chars.count, start + width)
        let typed = String(chars[start..<min(cursor, end)])
        let current = cursor < end ? String(chars[cursor]) : ""
        let upcomingStart = min(cursor + 1, end)
        let upcoming = String(chars[upcomingStart..<end])
        return Window(typed: typed, current: current, upcoming: upcoming)
    }

    // MARK: Normalizing

    /// Collapse newlines and runs of spaces, and straighten smart quotes so the guide is one clean line.
    static func normalize(_ raw: String) -> String {
        var s = raw
        for (fancy, plain) in [("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201C}", "\""), ("\u{201D}", "\""),
                               ("\u{2013}", "-"), ("\u{2014}", "-"), ("\u{00A0}", " ")] {
            s = s.replacingOccurrences(of: fancy, with: plain)
        }
        let parts = s.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return parts.joined(separator: " ")
    }

    /// Lower-case and straighten a single character so comparisons are forgiving.
    static func fold(_ c: Character) -> Character {
        if c.isWhitespace { return " " }
        switch c {
        case "\u{2018}", "\u{2019}": return "'"
        case "\u{201C}", "\u{201D}": return "\""
        case "\u{2013}", "\u{2014}": return "-"
        default: return Character(c.lowercased())
        }
    }
}
