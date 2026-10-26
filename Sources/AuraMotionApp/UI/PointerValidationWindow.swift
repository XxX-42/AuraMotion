import AppKit
import SwiftUI
import QuartzCore
import AuraMotionCore

/// Opt-in target instrumentation. It observes the existing CGEvent output; it
/// neither computes pointer motion nor creates another event/settings path.
@MainActor
enum PointerValidationWindow {
    private static var window: NSWindow?
    static func show() {
        if window == nil {
            let model = PointerValidationModel()
            let created = NSWindow(contentRect: NSRect(x: 140, y: 120, width: 760, height: 510),
                                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            created.identifier = NSUserInterfaceItemIdentifier("AuraMotion Pointer Validation")
            created.isReleasedWhenClosed = false
            created.acceptsMouseMovedEvents = true
            created.contentView = NSHostingView(rootView: PointerValidationView(model: model))
            window = created
        }
        window?.title = L10n.tr("Pointer Target & Drag Test")
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct ValidationEvent: Codable, Sendable {
    let timestamp: Double
    let x: Double
    let y: Double
    let kind: String
    let source: String
    let preset: String
}

private struct ValidationTrial: Codable, Sendable {
    let task: String
    let targetFraction: Double
    let errorPoints: Double
    let overshootPoints: Double
    let elapsedMs: Double
    let maxStepPoints: Double
}

private struct ValidationRun: Codable, Sendable {
    let source: String
    let unit: String
    let started: Date
    let settingsAtStart: CursorExperimentSettings
    let widthPoints: Double
    let heightPoints: Double
    let trials: [ValidationTrial]
    let events: [ValidationEvent]
    let eventLimitReached: Bool
}

@MainActor
private final class PointerValidationModel: ObservableObject {
    enum Mode { case targets, drag }
    @Published var running = false
    @Published var statusKey = "Ready"
    @Published var lastExportURL: URL?
    @Published var index = 0
    var size = CGSize(width: 720, height: 350)
    private(set) var mode: Mode = .targets
    private var events: [ValidationEvent] = []
    private var trials: [ValidationTrial] = []
    private var runs: [ValidationRun] = []
    private var settingsAtStart = CursorExperimentSettings()
    private var started = Date()
    private var trialStarted: Double = 0
    private var origin: CGPoint?
    private var previous: CGPoint?
    private var maxStep = 0.0
    private var overshoot = 0.0
    private var dragging = false
    private let fractions = [0.1, 0.9, 0.5]
    private let capacity = 4096

    var target: CGPoint {
        CGPoint(x: size.width * (mode == .drag ? (dragging ? 0.9 : 0.1) : fractions[min(index, 2)]), y: size.height * 0.5)
    }

    func start(_ mode: Mode) {
        self.mode = mode
        events.removeAll(keepingCapacity: true)
        trials.removeAll(keepingCapacity: true)
        settingsAtStart = AppEnvironment.shared.currentSettings.cursorExperiment.normalized()
        started = Date()
        index = 0
        dragging = false
        origin = nil
        previous = nil
        maxStep = 0
        overshoot = 0
        trialStarted = CACurrentMediaTime()
        statusKey = mode == .targets ? "Target" : "Drag from the left circle to the right circle."
        running = true
    }

    func stop() { running = false; dragging = false }

    func observe(_ point: CGPoint, kind: String, gesture: Bool) {
        guard running, point.x.isFinite, point.y.isFinite else { return }
        let time = CACurrentMediaTime()
        if events.count < capacity {
            events.append(ValidationEvent(timestamp: time, x: point.x, y: point.y, kind: kind,
                source: gesture ? "AuraMotion_tagged_event" : "external_event",
                preset: AppEnvironment.shared.currentSettings.cursorExperiment.preset.rawValue))
        }
        // CUA/manual mouse actions must never count as successful gesture trials.
        guard gesture else { return }
        let goal = target
        if origin == nil { origin = point; trialStarted = time }
        if let previous { maxStep = max(maxStep, hypot(point.x - previous.x, point.y - previous.y)) }
        previous = point
        if let origin {
            let dx = goal.x - origin.x, dy = goal.y - origin.y
            let distance = hypot(dx, dy)
            if distance > 0 { overshoot = max(overshoot, ((point.x - goal.x) * dx + (point.y - goal.y) * dy) / distance) }
        }
        if mode == .targets, kind == "down" {
            trials.append(ValidationTrial(task: "target_acquisition", targetFraction: fractions[min(index, 2)],
                errorPoints: hypot(point.x - goal.x, point.y - goal.y), overshootPoints: max(0, overshoot),
                elapsedMs: (time - trialStarted) * 1000, maxStepPoints: maxStep))
            if index == 2 { finish(); return }
            index += 1
            origin = point
            trialStarted = time
            maxStep = 0
            overshoot = 0
        } else if mode == .drag {
            if kind == "down", !dragging, hypot(point.x - goal.x, point.y - goal.y) <= 35 {
                dragging = true
                origin = point
                previous = point
                trialStarted = time
                maxStep = 0
                overshoot = 0
                objectWillChange.send()
            } else if kind == "up", dragging {
                trials.append(ValidationTrial(task: "drag", targetFraction: 0.9,
                    errorPoints: hypot(point.x - goal.x, point.y - goal.y), overshootPoints: max(0, overshoot),
                    elapsedMs: (time - trialStarted) * 1000, maxStepPoints: maxStep))
                finish()
            }
        }
    }

    private func finish() {
        runs.append(ValidationRun(source: "live_tagged_CGEvent_target_task", unit: "Quartz/AppKit logical points (not Retina backing pixels)",
            started: started, settingsAtStart: settingsAtStart, widthPoints: size.width, heightPoints: size.height,
            trials: trials, events: events, eventLimitReached: events.count == capacity))
        if runs.count > 32 { runs.removeFirst(runs.count - 32) }
        stop()
        statusKey = "Task complete"
    }

    func export() {
        guard !runs.isEmpty else { statusKey = "No task results yet"; return }
        let immutableRuns = runs
        DispatchQueue.global(qos: .utility).async {
            do {
                let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("AuraMotion/Experiments/TargetTasks", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent("targets_\(UUID().uuidString).json")
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(immutableRuns).write(to: url, options: .atomic)
                DispatchQueue.main.async { [weak self] in self?.lastExportURL = url; self?.statusKey = "Results exported" }
            } catch {
                DispatchQueue.main.async { [weak self] in self?.statusKey = "Metrics export failed." }
            }
        }
    }
}

private struct PointerValidationView: View {
    @ObservedObject var model: PointerValidationModel
    @ObservedObject private var localization = AppLocalization.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("Click three targets with the gesture pointer. Then test dragging inside this window."))
            HStack {
                Button(L10n.tr("Start Target Test")) { model.start(.targets) }
                Button(L10n.tr("Start Drag Test")) { model.start(.drag) }
                Button(L10n.tr("Export Task Results")) { model.export() }.disabled(model.running)
                Spacer()
                Text(L10n.tr(model.statusKey))
                if model.running, model.mode == .targets { Text("\(model.index + 1) / 3") }
            }
            ValidationCanvas(model: model).frame(minWidth: 500, minHeight: 300)
            if let url = model.lastExportURL { Text(url.path).font(.caption).textSelection(.enabled) }
        }
        .padding(16)
        .onDisappear { model.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            if (note.object as? NSWindow)?.identifier?.rawValue == "AuraMotion Pointer Validation" { model.stop() }
        }
    }
}

private struct ValidationCanvas: NSViewRepresentable {
    let model: PointerValidationModel
    func makeNSView(context: Context) -> ValidationCanvasView { ValidationCanvasView(model: model) }
    func updateNSView(_ view: ValidationCanvasView, context: Context) { view.needsDisplay = true }
}

@MainActor
private final class ValidationCanvasView: NSView {
    private let model: PointerValidationModel
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(model: PointerValidationModel) { self.model = model; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseMoved, .enabledDuringMouseDrag], owner: self)
        if let tracking { addTrackingArea(tracking) }
        super.updateTrackingAreas()
    }
    override func draw(_ dirtyRect: NSRect) {
        model.size = bounds.size
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        guard model.running else { return }
        let target = model.target
        NSColor.systemTeal.setFill()
        NSBezierPath(ovalIn: CGRect(x: target.x - 24, y: target.y - 24, width: 48, height: 48)).fill()
    }
    private func receive(_ event: NSEvent, kind: String) {
        let tagged = event.cgEvent?.getIntegerValueField(.eventSourceUserData) == kAuraMotionEventMagicTag
        model.observe(convert(event.locationInWindow, from: nil), kind: kind, gesture: tagged)
        needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) { receive(event, kind: "move") }
    override func mouseDown(with event: NSEvent) { receive(event, kind: "down") }
    override func mouseDragged(with event: NSEvent) { receive(event, kind: "drag") }
    override func mouseUp(with event: NSEvent) { receive(event, kind: "up") }
}
