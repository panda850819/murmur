import ApplicationServices
import MurmurCore

/// macOS `SelectionReading`: asks Accessibility for the focused UI element's
/// selected text. App-target glue (peer of `GlobalHotKeyMonitor`) — an AX
/// call is an input source, not part of the unit-tested flow. Rides the same
/// Accessibility grant the paste path already requires; ungranted or
/// unsupported (app exposes no AX selection) simply reads as "no selection",
/// and ask mode answers the question without reference text.
@MainActor
final class AXSelectionReader: SelectionReading {
    func selectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return nil
        }
        let focused = focusedRef as! AXUIElement

        var selectionRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selectionRef
        ) == .success, let text = selectionRef as? String, !text.isEmpty else {
            return nil
        }
        return text
    }
}
