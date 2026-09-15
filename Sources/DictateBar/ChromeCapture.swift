import AppKit

/// Reads the page you are looking at in Google Chrome.
///
/// Most pages (Canvas assignments, articles) give up their text through
/// JavaScript, which also picks up the teacher's instructions on the page.
/// Google Docs draws its text into <canvas> elements instead of the DOM, so
/// innerText comes back empty there — those fall back to Select All + Copy.
enum ChromeCapture {
    struct Page {
        let url: String
        let title: String
        let text: String

        /// The block handed to the AI, so it knows where the text came from.
        var promptBlock: String {
            "PAGE URL: \(url)\nPAGE TITLE: \(title)\n\nPAGE CONTENT:\n\n\(text)"
        }
    }

    /// What the caller should do next.
    enum Result {
        case page(Page)
        /// Chrome can't give us the text; use DocumentCapture instead. Carries the tab
        /// info when we have it, so a Google Doc still gets its title and URL.
        case useFrontDocument(url: String, title: String)
        case failure(Error)
    }

    enum CaptureError: LocalizedError {
        case notRunning
        case noTab
        case needsAutomation
        case needsJavaScriptPermission
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .notRunning:
                return "Google Chrome isn't running"
            case .noTab:
                return "No open Chrome tab"
            case .needsAutomation:
                return "Allow DictateBar to control Chrome (System Settings → Privacy → Automation)"
            case .needsJavaScriptPermission:
                return "Turn on Chrome → View → Developer → Allow JavaScript from Apple Events"
            case .scriptFailed(let detail):
                return "Chrome: \(detail)"
            }
        }
    }

    /// Google Docs (and Slides/Sheets) render text to a canvas — JavaScript can't read it.
    static func rendersToCanvas(_ url: String) -> Bool {
        ["docs.google.com/document", "docs.google.com/presentation", "docs.google.com/spreadsheets"]
            .contains { url.contains($0) }
    }

    static func capture() -> Result {
        let tab: (url: String, title: String)
        do {
            tab = try activeTab()
        } catch {
            return .failure(error)
        }

        if rendersToCanvas(tab.url) {
            return .useFrontDocument(url: tab.url, title: tab.title)
        }

        do {
            let text = try pageText()
            guard text.count >= 40 else {
                // A near-empty page usually means another canvas-drawn editor.
                return .useFrontDocument(url: tab.url, title: tab.title)
            }
            return .page(Page(url: tab.url, title: tab.title, text: text))
        } catch {
            return .failure(error)
        }
    }

    // MARK: AppleScript

    private static func activeTab() throws -> (url: String, title: String) {
        let script = """
        tell application "Google Chrome"
            if not running then return "!NOTRUNNING"
            if (count of windows) is 0 then return "!NOTAB"
            set theTab to active tab of front window
            return (URL of theTab) & linefeed & (title of theTab)
        end tell
        """
        let raw = try run(script)
        if raw.hasPrefix("!NOTRUNNING") { throw CaptureError.notRunning }
        if raw.hasPrefix("!NOTAB") { throw CaptureError.noTab }
        let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let url = parts.first, !url.isEmpty else { throw CaptureError.noTab }
        return (url, parts.count > 1 ? parts[1] : "")
    }

    /// Prefers the main article region so navigation chrome and footers stay out.
    private static func pageText() throws -> String {
        let js = "(function(){var m=document.querySelector('main,article,[role=main]');"
            + "var t=((m||document.body)||{}).innerText||'';return t.replace(/\\n{3,}/g,'\\n\\n').trim();})()"
        let script = """
        tell application "Google Chrome"
            if not running then return "!NOTRUNNING"
            if (count of windows) is 0 then return "!NOTAB"
            return execute front window's active tab javascript "\(escapeForAppleScript(js))"
        end tell
        """
        let raw = try run(script)
        if raw.hasPrefix("!NOTRUNNING") { throw CaptureError.notRunning }
        if raw.hasPrefix("!NOTAB") { throw CaptureError.noTab }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func run(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw CaptureError.scriptFailed("could not compile the script")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "unknown error"
            let number = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            // -1743: the user has not granted Automation access for Chrome.
            if number == -1743 || message.contains("Not authorized") { throw CaptureError.needsAutomation }
            if message.contains("JavaScript") || message.contains("Apple Events") {
                throw CaptureError.needsJavaScriptPermission
            }
            throw CaptureError.scriptFailed(message)
        }
        return result.stringValue ?? ""
    }
}
