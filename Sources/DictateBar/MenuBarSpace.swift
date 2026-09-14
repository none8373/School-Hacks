import AppKit
import ApplicationServices

/// Measures the empty stretch of menu bar left of the notch, using Accessibility
/// to read where the front app's menus end.
enum MenuBarSpace {
    private static let axTimeout: Float = 0.1

    /// The stretch of menu bar our line may use: from the front app's menus (or, when
    /// covering menus, from just after the app's name) to the notch or our own status icon.
    static func freeGap(on screen: NSScreen, ourItemMinX: CGFloat?, coverAppMenus: Bool) -> ClosedRange<CGFloat> {
        let menusEnd = coverAppMenus ? frontAppNameMaxX() : frontAppMenuMaxX()
        let left = (menusEnd ?? screen.frame.minX + screen.frame.width * 0.3) + 10
        let right: CGFloat
        if let notch = screen.auxiliaryTopLeftArea {
            right = notch.maxX - 6
        } else {
            right = (ourItemMinX ?? screen.frame.maxX - 400) - 10
        }
        return left...max(left, right)
    }

    /// Right edge of the front app's last menu title.
    private static func frontAppMenuMaxX() -> CGFloat? {
        menuBarItems()?.last.flatMap(maxX)
    }

    /// Right edge of the app's bold name (the first title after the Apple menu).
    private static func frontAppNameMaxX() -> CGFloat? {
        guard let items = menuBarItems(), items.count >= 2 else { return frontAppMenuMaxX() }
        return maxX(items[1])
    }

    private static func menuBarItems() -> [AXUIElement]? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let ax = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, axTimeout)
        guard let bar = element(ax, kAXMenuBarAttribute) else { return nil }
        let items = children(of: bar)
        return items.isEmpty ? nil : items
    }

    private static func maxX(_ item: AXUIElement) -> CGFloat? {
        guard let pos = position(of: item), let sz = size(of: item) else { return nil }
        return pos.x + sz.width
    }

    /// True when a full-screen window is on screen: some normal window covers the whole
    /// display, menu bar area included. (Accessibility's AXFullScreen is unreliable in Chrome.)
    static func frontWindowIsFullScreen() -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let target = screen.frame
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"] else { continue }
            // Full-screen windows start at the top (or just under the notch band) and reach the bottom edge.
            let menuBar = target.maxY - screen.visibleFrame.maxY
            if abs(x - target.minX) < 1, y <= menuBar + 1, abs(w - target.width) < 1, y + h >= target.height - 1 { return true }
        }
        return false
    }

    // MARK: AX helpers

    private static func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, name as CFString, &value) == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(of parent: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func size(of element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let value else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    private static func position(of element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }
}
