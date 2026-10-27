#if DEBUG
import AppKit
import AuraMotionCore

/// Non-interactive panel; target selection and AX calls stay in AuraMotionCore.
@MainActor
final class AccessibilityTargetHighlightWindow {
    private let panel: NSPanel
    private let view = HighlightView()
    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = view
        panel.setAccessibilityElement(false)
    }
    func update(_ snapshot: AccessibilityTargetSnapshot?, state: String) {
        guard let snapshot, let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        }) else { panel.orderOut(nil); return }
        let frame = snapshot.frame, expanded = AccessibilityTargetScorer.effectiveFrame(frame)
        let quartz = CGDisplayBounds(CGMainDisplayID())
        // Quartz origin is top-left; AppKit origin is bottom-left.
        let appKitFrame = NSRect(x: screen.frame.minX + expanded.minX - quartz.minX,
                                 y: screen.frame.maxY - (expanded.maxY - quartz.minY),
                                 width: expanded.width, height: expanded.height)
        view.visual = NSRect(x: frame.minX-expanded.minX, y: expanded.maxY-frame.maxY, width: frame.width, height: frame.height)
        view.locked = state == "locked"; view.candidate = state.hasPrefix("candidate"); view.needsDisplay = true
        panel.setFrame(appKitFrame, display: true); panel.orderFrontRegardless()
    }
}
private final class HighlightView: NSView {
    var visual = NSRect.zero
    var locked = false
    var candidate = false
    override func accessibilityIsIgnored() -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let color = candidate ? NSColor.systemYellow : NSColor.systemCyan
        color.withAlphaComponent(0.12).setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9).fill()
        color.withAlphaComponent(0.9).setStroke()
        let outer = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 9, yRadius: 9); outer.lineWidth = 2; outer.stroke()
        let inner = NSBezierPath(rect: visual.insetBy(dx: 0.5, dy: 0.5)); inner.lineWidth = 1; inner.stroke()
    }
}
#endif
