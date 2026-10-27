#if DEBUG
import AppKit
import AuraMotionCore

/// Visualizes gaze without moving the system pointer or intercepting input.
@MainActor
final class GazeProjectionWindow {
    private let panel: NSPanel
    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = ProjectionView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        panel.setAccessibilityElement(false)
    }
    func update(_ point: CGPoint?) {
        guard let point, let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        }), let frame = GazeProjectionPlacement.panelFrame(point: point, quartzDisplay: CGDisplayBounds(CGMainDisplayID()), appKitDisplay: screen.frame, size: 32) else {
            panel.orderOut(nil); return
        }
        panel.setFrame(frame, display: true); panel.orderFrontRegardless()
    }
}
private final class ProjectionView: NSView {
    override func accessibilityIsIgnored() -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4))
        NSColor.black.withAlphaComponent(0.70).setFill(); circle.fill()
        NSColor.systemCyan.setStroke(); circle.lineWidth = 2; circle.stroke()
        let cross = NSBezierPath(); cross.move(to: NSPoint(x: 16, y: 9)); cross.line(to: NSPoint(x: 16, y: 23))
        cross.move(to: NSPoint(x: 9, y: 16)); cross.line(to: NSPoint(x: 23, y: 16))
        NSColor.white.setStroke(); cross.lineWidth = 2; cross.stroke()
    }
}
#endif
