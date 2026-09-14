import AppKit
import SwiftUI

/// How the menu bar line looks. Stored inside Settings; empty color = system default.
struct Appearance: Codable, Equatable {
    enum FontStyle: String, Codable, CaseIterable { case mono, system, rounded }
    enum Background: String, Codable, CaseIterable { case none, pill, solid }

    var textColor = ""          // hex like "#FFFFFF"; "" = system label colour
    var typedColor = ""         // already-typed characters; "" = faint label colour
    var highlightColor = ""     // background behind the next character; "" = accent colour
    var highlightTextColor = "#FFFFFF"
    var suggestionColor = ""    // "" = secondary label colour
    var fontStyle: FontStyle = .mono
    var fontSize: Double = 12
    var background: Background = .none
    var backgroundColor = "#000000"
    var backgroundOpacity: Double = 0.5
    var cornerRadius: Double = 6
    var showSuggestion = true

    // MARK: Resolved values

    var font: NSFont {
        let size = CGFloat(fontSize)
        switch fontStyle {
        case .mono: return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .system: return .systemFont(ofSize: size)
        case .rounded:
            let base = NSFont.systemFont(ofSize: size)
            return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
        }
    }

    /// Average character width, used to work out how many characters fit.
    var charWidth: CGFloat {
        let sample = fontStyle == .mono ? "n" : "abcdefghijklmnopqrstuvwxyz "
        let width = (sample as NSString).size(withAttributes: [.font: font]).width
        return width / CGFloat(sample.count)
    }

    var text: NSColor { NSColor(hex: textColor) ?? .labelColor }
    var typed: NSColor { NSColor(hex: typedColor) ?? .tertiaryLabelColor }
    var highlight: NSColor { NSColor(hex: highlightColor) ?? .controlAccentColor }
    var highlightText: NSColor { NSColor(hex: highlightTextColor) ?? .white }
    var suggestion: NSColor { NSColor(hex: suggestionColor) ?? .secondaryLabelColor }
    var backgroundNSColor: NSColor { (NSColor(hex: backgroundColor) ?? .black).withAlphaComponent(backgroundOpacity) }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

/// SwiftUI binding between a hex string in Settings and a ColorPicker.
struct HexColorBinding {
    static func make(_ hex: Binding<String>, fallback: NSColor) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: hex.wrappedValue) ?? fallback) },
            set: { hex.wrappedValue = NSColor($0).hexString }
        )
    }
}
