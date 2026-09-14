import AppKit
import ApplicationServices

/// Watches keystrokes system-wide (needs Accessibility permission).
/// Hotkeys are swallowed so other apps never see them; normal typing is only observed.
final class EventTap {
    enum Hotkey {
        case record, clipboard, notes, grade, classRecord, pasteNotes, writeSuggestion, nextSuggestion, doneSuggestion, openWindow,
             playPause, hide, wordBack, wordForward, sentenceBack, sentenceForward
    }

    enum Typed {
        case character(Character)
        case backspace
    }

    var modifier: Settings.Modifier = .option
    var capsLockAutoType = true
    var onHotkey: ((Hotkey) -> Void)?
    var onTyped: ((Typed) -> Void)?
    /// Caps Lock mode: asked for the next character to type instead of the one pressed. Return nil to leave the key alone.
    var onAutoType: (() -> Character?)?
    var onFlagsChanged: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    static func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Returns false if macOS refused (Accessibility not granted yet).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: refcon
        ) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Returns true if the event was a hotkey and should be swallowed.
    fileprivate func handle(_ event: CGEvent) -> Bool {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let option = flags.contains(.maskAlternate)
        let control = flags.contains(.maskControl)
        let command = flags.contains(.maskCommand)

        let modifierHeld: Bool
        switch modifier {
        case .option: modifierHeld = option && !control && !command
        case .controlOption: modifierHeld = option && control && !command
        }

        if modifierHeld, let hotkey = EventTap.hotkey(for: keyCode) {
            onHotkey?(hotkey)
            return true
        }

        // Ordinary typing. Skip app shortcuts like Cmd+S.
        guard !command, !control else { return false }
        if keyCode == 51 {
            onTyped?(.backspace)
            return false
        }
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buffer)
        let text = String(utf16CodeUnits: buffer, count: length)

        // Caps Lock mode: swap whatever key was pressed for the next character of the guide.
        if capsLockAutoType, flags.contains(.maskAlphaShift), !option, isPrintable(text),
           let replacement = onAutoType?() {
            var units = Array(String(replacement).utf16)
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            event.flags = []
            return false
        }
        if let c = text.first, !c.isNewline, c.asciiValue.map({ $0 >= 32 }) ?? true {
            onTyped?(.character(c))
        } else if let c = text.first, c.isNewline {
            onTyped?(.character(" "))
        }
        return false
    }

    private func isPrintable(_ text: String) -> Bool {
        guard let c = text.first else { return false }
        if c.isNewline { return false }
        if let ascii = c.asciiValue { return ascii >= 32 && ascii != 127 }
        return true
    }

    private static func hotkey(for keyCode: Int) -> Hotkey? {
        switch keyCode {
        case 15: return .record          // R
        case 9: return .clipboard        // V
        case 45: return .notes           // N
        case 5: return .grade            // G
        case 8: return .classRecord      // C
        case 35: return .pasteNotes      // P
        case 13: return .writeSuggestion // W
        case 38: return .nextSuggestion  // J
        case 2: return .doneSuggestion   // D
        case 31: return .openWindow      // O
        case 49: return .playPause       // Space
        case 4: return .hide             // H
        case 123: return .wordBack       // Left
        case 124: return .wordForward    // Right
        case 126: return .sentenceBack   // Up
        case 125: return .sentenceForward // Down
        default: return nil
        }
    }
}

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        tap.reenable()
        return Unmanaged.passUnretained(event)
    }
    if type == .flagsChanged {
        tap.onFlagsChanged?()
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown else { return Unmanaged.passUnretained(event) }
    return tap.handle(event) ? nil : Unmanaged.passUnretained(event)
}
