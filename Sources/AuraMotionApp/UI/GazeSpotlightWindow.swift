#if DEBUG
import AppKit
import AuraMotionCore

/// A visual-only screen overlay. It never intercepts mouse or AX input.
@MainActor
final class GazeSpotlightWindow {
    static let toggleNotification = Notification.Name("AuraMotionGazeSpotlightToggle")
    private let panel: NSPanel
    private let spotlightView = SpotlightView()
    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = spotlightView
        panel.setAccessibilityElement(false)
    }
    func update(_ point: CGPoint?, enabled: Bool) {
        guard enabled, let point, let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        }), let marker = GazeProjectionPlacement.panelFrame(point: point, quartzDisplay: CGDisplayBounds(CGMainDisplayID()), appKitDisplay: screen.frame, size: 32) else {
            panel.orderOut(nil); return
        }
        let center = CGPoint(x: marker.midX - screen.frame.minX, y: marker.midY - screen.frame.minY)
        let localScreen = CGRect(origin: .zero, size: screen.frame.size)
        guard let quadrant = GazeSpotlightGeometry.largestOverlapQuadrant(center: center, screen: localScreen, previous: spotlightView.quadrant) else {
            panel.orderOut(nil); return
        }
        let frameChanged = panel.frame != screen.frame
        if frameChanged { panel.setFrame(screen.frame, display: false) }
        if frameChanged || spotlightView.quadrant != quadrant {
            spotlightView.quadrant = quadrant; spotlightView.needsDisplay = true
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}
private final class SpotlightView: NSView {
    var quadrant: ScreenQuadrant?
    override func accessibilityIsIgnored() -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let quadrant else { return }
        let highlight = GazeSpotlightGeometry.quadrantRect(quadrant, screen: bounds)
        let outside = NSBezierPath(rect: bounds)
        outside.appendRect(highlight)
        outside.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(GazeSpotlightGeometry.dimOpacity).setFill()
        outside.fill()
        NSColor.white.withAlphaComponent(GazeSpotlightGeometry.highlightOpacity).setFill()
        NSBezierPath(rect: highlight).fill()
    }
}
#endif
