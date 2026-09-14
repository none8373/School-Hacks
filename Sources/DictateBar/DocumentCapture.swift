import AppKit

/// Grabs all the text of the front document by sending Select All + Copy, then
/// collapses the selection and puts the user's old clipboard back.
enum DocumentCapture {
    static func frontDocumentText(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        let previousCount = pasteboard.changeCount

        post(keyCode: 0, command: true)   // Cmd+A
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            post(keyCode: 8, command: true)   // Cmd+C
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                post(keyCode: 124, command: false)   // Right arrow: drop the selection
                let text = pasteboard.changeCount != previousCount ? pasteboard.string(forType: .string) : nil
                if let previous {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
                completion(text)
            }
        }
    }

    /// Cmd+V into the front app.
    static func paste() {
        post(keyCode: 9, command: true)
    }

    private static func post(keyCode: CGKeyCode, command: Bool) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = command ? .maskCommand : []
            event.post(tap: .cghidEventTap)
        }
    }
}
