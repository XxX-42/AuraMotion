#if DEBUG
import AppKit
import AuraMotionCore

/// Visualizes gaze without moving the system pointer or intercepting input.
@MainActor
final class GazeProjectionWindow {
    private let panel: NSPanel
    private let projectionView = ProjectionView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
    init(color: NSColor = .systemCyan) {
        projectionView.color = color
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = projectionView
        panel.setAccessibilityElement(false)
    }
    func update(_ point: CGPoint?, stale: Bool = false) {
        guard let point, let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        }), let frame = GazeProjectionPlacement.panelFrame(point: point, quartzDisplay: CGDisplayBounds(CGMainDisplayID()), appKitDisplay: screen.frame, size: 32) else {
            panel.orderOut(nil); return
        }
        projectionView.stale = stale; projectionView.needsDisplay = true
        panel.setFrame(frame, display: true); panel.orderFrontRegardless()
    }
}
private final class ProjectionView: NSView {
    var stale = false
    var color = NSColor.systemCyan
    override func accessibilityIsIgnored() -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4))
        NSColor.black.withAlphaComponent(0.70).setFill(); circle.fill()
        color.withAlphaComponent(stale ? 0.4 : 1).setStroke(); circle.lineWidth = 2; circle.stroke()
        let cross = NSBezierPath(); cross.move(to: NSPoint(x: 16, y: 9)); cross.line(to: NSPoint(x: 16, y: 23))
        cross.move(to: NSPoint(x: 9, y: 16)); cross.line(to: NSPoint(x: 23, y: 16))
        NSColor.white.withAlphaComponent(stale ? 0.4 : 1).setStroke(); cross.lineWidth = 2; cross.stroke()
    }
}
#endif
