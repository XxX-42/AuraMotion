import AppKit
import SwiftUI
import AuraMotionCore

/// Non-activating floating NSPanel for the HUD.
/// Floats above normal application windows without stealing key focus.
@MainActor
public final class FloatingHUDWindow: NSPanel {
    private var resizeStartFrame: NSRect?
    private var moveStartFrame: NSRect?
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isFloatingPanel = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.ignoresMouseEvents = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.contentMinSize = NSSize(width: 220, height: 200)
    }

    public func saveHUDSize() {
        guard frame.width >= 220, frame.height >= 200 else { return }
        UserDefaults.standard.set(frame.width, forKey: "hudWindowWidth")
        UserDefaults.standard.set(frame.height, forKey: "hudWindowHeight")
    }

    public func restoreDefaultSize() {
        let current = frame
        setFrame(NSRect(x: current.maxX - 480, y: current.maxY - 360, width: 480, height: 360),
                 display: true, animate: true)
        saveHUDSize()
    }

    public func resizeFromHandle(translation: CGSize, finished: Bool) {
        if finished {
            resizeStartFrame = nil
            saveHUDSize()
            return
        }
        let start = resizeStartFrame ?? frame
        resizeStartFrame = start
        let visible = screen?.visibleFrame
        let maximumWidth = visible.map { max(220, start.maxX - $0.minX) } ?? CGFloat.greatestFiniteMagnitude
        let maximumHeight = visible.map { max(200, start.maxY - $0.minY) } ?? CGFloat.greatestFiniteMagnitude
        let width = min(maximumWidth, max(220, start.width - translation.width))
        let height = min(maximumHeight, max(200, start.height + translation.height))
        setFrame(NSRect(x: start.maxX - width, y: start.maxY - height, width: width, height: height), display: true)
    }

    public func moveFromHeader(translation: CGSize, finished: Bool) {
        if finished {
            moveStartFrame = nil
            return
        }
        let start = moveStartFrame ?? frame
        moveStartFrame = start
        setFrameOrigin(NSPoint(x: start.minX + translation.width, y: start.minY + translation.height))
    }
}
