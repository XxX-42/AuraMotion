import CoreGraphics
import Foundation

/// Identifies whether a trace came from an actual camera run or generated input.
/// The source is mandatory so synthetic numbers can never be mistaken for camera results.
public enum CursorExperimentSource: String, Codable, Sendable, CaseIterable {
    case camera
    case synthetic
}

public struct CursorExperimentCameraMetadata: Codable, Sendable, Equatable {
    /// Human-readable camera label only. Device unique identifiers are intentionally omitted.
    public let name: String?
    public let width: Int?
    public let height: Int?
    public let nominalFPS: Double?

    public init(name: String? = nil, width: Int? = nil, height: Int? = nil, nominalFPS: Double? = nil) {
        self.name = name
        self.width = width
        self.height = height
        self.nominalFPS = nominalFPS?.isFinite == true ? nominalFPS : nil
    }
}

/// ROI metadata is expressed in normalized image coordinates, never as an image crop.
public struct CursorExperimentROI: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let usedFullFrame: Bool
    public let fallbackReason: String?

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        usedFullFrame: Bool,
        fallbackReason: String? = nil
    ) {
        self.x = x.isFinite ? x : 0
        self.y = y.isFinite ? y : 0
        self.width = width.isFinite ? width : 0
        self.height = height.isFinite ? height : 0
        self.usedFullFrame = usedFullFrame
        self.fallbackReason = fallbackReason
    }

    public init(rect: CGRect, usedFullFrame: Bool, fallbackReason: String? = nil) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.width),
            height: Double(rect.height),
            usedFullFrame: usedFullFrame,
            fallbackReason: fallbackReason
        )
    }
}

/// A Codable copy of the controller diagnostics captured after processing a frame.
public struct CursorExperimentMotionSample: Codable, Sendable, Equatable {
    public let timestamp: Double
    public let rawAnchor: CGPoint
    public let filtered: CGPoint
    public let cursor: CGPoint
    public let speed: Double
    public let deadzone: Double
    public let gain: Double
    public let phase: CursorMotionPhase

    public init(
        timestamp: Double,
        rawAnchor: CGPoint,
        filtered: CGPoint,
        cursor: CGPoint,
        speed: Double,
        deadzone: Double,
        gain: Double,
        phase: CursorMotionPhase
    ) {
        self.timestamp = timestamp
        self.rawAnchor = rawAnchor
        self.filtered = filtered
        self.cursor = cursor
        self.speed = speed.isFinite ? speed : 0
        self.deadzone = deadzone.isFinite ? deadzone : 0
        self.gain = gain.isFinite ? gain : 1
        self.phase = phase
    }

    public init(diagnostics: CursorMotionDiagnostics) {
        self.init(
            timestamp: diagnostics.timestamp,
            rawAnchor: diagnostics.rawAnchor,
            filtered: diagnostics.filtered,
            cursor: diagnostics.cursor,
            speed: diagnostics.speed,
            deadzone: diagnostics.deadzone,
            gain: diagnostics.gain,
            phase: diagnostics.phase
        )
    }
}

public enum CursorExperimentTaskPhase: String, Codable, Sendable, CaseIterable {
    case stationary
    case slowMove
    case fastMove
    case acquisition
    case dragging
    case other
}

public enum CursorExperimentTaskEvent: String, Codable, Sendable, CaseIterable {
    case click
    case dragStart
    case dragEnd
}

/// Optional ground-truth annotations. Points use Quartz global display coordinates.
/// A missing annotation means accuracy and task-time metrics are unavailable.
public struct CursorExperimentGroundTruth: Codable, Sendable, Equatable {
    public let target: CGPoint
    public let phase: CursorExperimentTaskPhase
    public let segmentID: String?
    public let segmentStart: CGPoint?
    public let segmentEnd: CGPoint?
    public let event: CursorExperimentTaskEvent?

    public init(
        target: CGPoint,
        phase: CursorExperimentTaskPhase,
        segmentID: String? = nil,
        segmentStart: CGPoint? = nil,
        segmentEnd: CGPoint? = nil,
        event: CursorExperimentTaskEvent? = nil
    ) {
        self.target = target
        self.phase = phase
        self.segmentID = segmentID
        self.segmentStart = segmentStart
        self.segmentEnd = segmentEnd
        self.event = event
    }
}

/// One bounded recorder entry. `timestamp` is monotonic host time in seconds.
public struct CursorExperimentFrame: Codable, Sendable, Equatable {
    public let timestamp: Double
    public let source: CursorExperimentSource
    public let sample: HandSample?
    public let state: GestureState?
    public let inferenceDurationMilliseconds: Double?
    public let mailboxWaitMilliseconds: Double?
    /// Cumulative mailbox drops as observed at this frame, when the source exposes them.
    public let droppedFrames: Int?
    public let roi: CursorExperimentROI?
    public let motion: CursorExperimentMotionSample?
    public let groundTruth: CursorExperimentGroundTruth?

    public init(
        timestamp: Double,
        source: CursorExperimentSource,
        sample: HandSample?,
        state: GestureState? = nil,
        inferenceDurationMilliseconds: Double? = nil,
        mailboxWaitMilliseconds: Double? = nil,
        droppedFrames: Int? = nil,
        roi: CursorExperimentROI? = nil,
        motion: CursorExperimentMotionSample? = nil,
        groundTruth: CursorExperimentGroundTruth? = nil
    ) {
        self.timestamp = timestamp
        self.source = source
        self.sample = sample
        self.state = state
        self.inferenceDurationMilliseconds = inferenceDurationMilliseconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.mailboxWaitMilliseconds = mailboxWaitMilliseconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.droppedFrames = droppedFrames.map { max(0, $0) }
        self.roi = roi
        self.motion = motion
        self.groundTruth = groundTruth
    }
}

public struct CursorExperimentRecordingMetadata: Codable, Sendable, Equatable {
    public let settings: CursorExperimentSettings
    public let calibrationProfile: CalibrationProfile
    public let calibrationProfileIsRecorded: Bool
    public let initialCursorPosition: CGPoint?
    /// Optional user-declared purpose for an unsegmented camera recording.
    /// This can identify stationary/slow/fast observations without inventing targets.
    public let declaredTaskPhase: CursorExperimentTaskPhase?
    public let provider: String?
    public let providerAvailabilityReason: String?
    public let camera: CursorExperimentCameraMetadata?

    public init(
        settings: CursorExperimentSettings = .init(),
        calibrationProfile: CalibrationProfile = .init(),
        calibrationProfileIsRecorded: Bool = true,
        initialCursorPosition: CGPoint? = nil,
        declaredTaskPhase: CursorExperimentTaskPhase? = nil,
        provider: String? = nil,
        providerAvailabilityReason: String? = nil,
        camera: CursorExperimentCameraMetadata? = nil
    ) {
        self.settings = settings.normalized()
        self.calibrationProfile = calibrationProfile
        self.calibrationProfileIsRecorded = calibrationProfileIsRecorded
        self.initialCursorPosition = initialCursorPosition.flatMap(Self.finitePoint)
        self.declaredTaskPhase = declaredTaskPhase
        self.provider = provider
        self.providerAvailabilityReason = providerAvailabilityReason
        self.camera = camera
    }

    private static func finitePoint(_ point: CGPoint) -> CGPoint? {
        point.x.isFinite && point.y.isFinite ? point : nil
    }
}

/// Immutable snapshot used by replay and export. Landmark samples contain only normalized joints.
public struct CursorExperimentRecording: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let sessionID: String
    public let startTime: Date
    public let source: CursorExperimentSource
    public let durationLimitSeconds: Double
    public let capacity: Int
    public let framesDroppedAtCapacity: Int
    public let framesRejectedForSourceMismatch: Int
    public let metadata: CursorExperimentRecordingMetadata
    public let frames: [CursorExperimentFrame]

    public init(
        schemaVersion: Int = CursorExperimentRecording.currentSchemaVersion,
        sessionID: String,
        startTime: Date,
        source: CursorExperimentSource,
        durationLimitSeconds: Double,
        capacity: Int,
        framesDroppedAtCapacity: Int = 0,
        framesRejectedForSourceMismatch: Int = 0,
        metadata: CursorExperimentRecordingMetadata = .init(),
        frames: [CursorExperimentFrame]
    ) {
        self.schemaVersion = schemaVersion
        self.sessionID = sessionID
        self.startTime = startTime
        self.source = source
        self.durationLimitSeconds = durationLimitSeconds
        self.capacity = capacity
        self.framesDroppedAtCapacity = max(0, framesDroppedAtCapacity)
        self.framesRejectedForSourceMismatch = max(0, framesRejectedForSourceMismatch)
        self.metadata = metadata
        self.frames = frames
    }
}

/// Live export document. It includes both the bounded anonymized landmark trace and
/// baseline/optimized metrics derived from that exact trace.
public struct CursorExperimentExportDocument: Codable, Sendable, Equatable {
    public let recording: CursorExperimentRecording
    public let replay: CursorExperimentReplayReport

    public init(recording: CursorExperimentRecording, replay: CursorExperimentReplayReport) {
        self.recording = recording
        self.replay = replay
    }
}

/// An opt-in, fixed-capacity ring buffer. It never writes files or starts a worker.
/// Call `snapshot()`/`stop()` on the interaction queue and export the copy elsewhere.
public final class CursorExperimentMetricsRecorder: @unchecked Sendable {
    public static let defaultCapacity = 1_800
    public static let maximumCapacity = 3_600
    public static let maximumDurationSeconds = 300.0

    private let lock = NSLock()
    private let capacity: Int
    private var slots: [CursorExperimentFrame?] = []
    private var nextWriteIndex = 0
    private var storedCount = 0
    private var sessionID = UUID().uuidString
    private var wallStartTime = Date()
    private var source: CursorExperimentSource = .camera
    private var durationLimit = 30.0
    private var metadata = CursorExperimentRecordingMetadata()
    private var firstTimestamp: Double?
    private var lastTimestamp: Double?
    private var droppedAtCapacity = 0
    private var rejectedSourceMismatch = 0
    private var active = false
    private var stopSnapshotConsumed = false

    public init(capacity: Int = CursorExperimentMetricsRecorder.defaultCapacity) {
        self.capacity = min(Self.maximumCapacity, max(1, capacity))
    }

    public var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    /// Allocates the bounded ring only after explicit opt-in.
    public func start(
        duration: Double,
        source: CursorExperimentSource,
        metadata: CursorExperimentRecordingMetadata = .init()
    ) {
        lock.lock()
        defer { lock.unlock() }
        slots = Array(repeating: nil, count: capacity)
        nextWriteIndex = 0
        storedCount = 0
        sessionID = UUID().uuidString
        wallStartTime = Date()
        self.source = source
        durationLimit = duration.isFinite
            ? min(Self.maximumDurationSeconds, max(0.1, duration))
            : 30.0
        self.metadata = metadata
        firstTimestamp = nil
        lastTimestamp = nil
        droppedAtCapacity = 0
        rejectedSourceMismatch = 0
        active = true
        stopSnapshotConsumed = false
    }

    /// Returns true only when the frame was accepted into the ring.
    @discardableResult
    public func record(frame: CursorExperimentFrame) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard active, !slots.isEmpty else { return false }
        guard frame.source == source else {
            rejectedSourceMismatch += 1
            return false
        }
        guard frame.timestamp.isFinite else { return false }
        if let lastTimestamp, frame.timestamp <= lastTimestamp { return false }
        if firstTimestamp == nil { firstTimestamp = frame.timestamp }
        if let firstTimestamp, frame.timestamp - firstTimestamp >= durationLimit {
            active = false
            return false
        }

        slots[nextWriteIndex] = frame
        nextWriteIndex = (nextWriteIndex + 1) % capacity
        if storedCount < capacity {
            storedCount += 1
        } else {
            droppedAtCapacity += 1
        }
        lastTimestamp = frame.timestamp
        return true
    }

    /// Stops recording and returns a value copy. Returns nil if never started or reset.
    public func stop() -> CursorExperimentRecording? {
        lock.lock()
        defer { lock.unlock() }
        guard !slots.isEmpty, !stopSnapshotConsumed else { return nil }
        active = false
        stopSnapshotConsumed = true
        return makeSnapshot()
    }

    /// Copies the current bounded trace without changing the recording state.
    public func snapshot() -> CursorExperimentRecording? {
        lock.lock()
        defer { lock.unlock() }
        guard !slots.isEmpty else { return nil }
        return makeSnapshot()
    }

    /// Releases retained frame memory and stops any active recording.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        active = false
        slots.removeAll(keepingCapacity: false)
        storedCount = 0
        nextWriteIndex = 0
        firstTimestamp = nil
        lastTimestamp = nil
        droppedAtCapacity = 0
        rejectedSourceMismatch = 0
        stopSnapshotConsumed = true
    }

    private func makeSnapshot() -> CursorExperimentRecording {
        let startIndex = storedCount == capacity ? nextWriteIndex : 0
        var frames: [CursorExperimentFrame] = []
        frames.reserveCapacity(storedCount)
        for offset in 0..<storedCount {
            let index = (startIndex + offset) % capacity
            if let frame = slots[index] { frames.append(frame) }
        }
        return CursorExperimentRecording(
            sessionID: sessionID,
            startTime: wallStartTime,
            source: source,
            durationLimitSeconds: durationLimit,
            capacity: capacity,
            framesDroppedAtCapacity: droppedAtCapacity,
            framesRejectedForSourceMismatch: rejectedSourceMismatch,
            metadata: metadata,
            frames: frames
        )
    }
}

public enum CursorExperimentExportError: Error, LocalizedError {
    case unsupportedExtension(String)
    case noFrames

    public var errorDescription: String? {
        switch self {
        case .unsupportedExtension(let value): return "Unsupported cursor experiment export extension: \(value)"
        case .noFrames: return "The cursor experiment contains no frames to export."
        }
    }
}

/// Synchronous serializers only. Call from an export queue, never the interaction queue.
public enum CursorExperimentMetricsExporter {
    public static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }

    public static func writeCSV(_ report: CursorExperimentReplayReport, to url: URL) throws -> URL {
        guard report.runs.contains(where: { !$0.rows.isEmpty }) else { throw CursorExperimentExportError.noFrames }
        let header = [
            "timestamp", "source", "mode", "raw_anchor_x", "raw_anchor_y", "filtered_x", "filtered_y",
            "cursor_x", "cursor_y", "speed", "deadzone", "gain", "state", "phase",
            "target_x", "target_y", "target_phase", "target_event"
        ].joined(separator: ",")
        var lines = [header]
        for run in report.runs {
            for row in run.rows {
                let fields = [
                    number(row.timestamp), row.source.rawValue, run.mode.rawValue,
                    number(row.rawAnchor?.x), number(row.rawAnchor?.y),
                    number(row.filtered?.x), number(row.filtered?.y),
                    number(row.cursor?.x), number(row.cursor?.y), number(row.speed),
                    number(row.deadzone), number(row.gain), row.state?.rawValue ?? "",
                    row.motionPhase?.rawValue ?? "", number(row.target?.x), number(row.target?.y),
                    row.targetPhase?.rawValue ?? "", row.targetEvent?.rawValue ?? ""
                ]
                lines.append(fields.map(csvEscape).joined(separator: ","))
            }
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public static func write(_ report: CursorExperimentReplayReport, to url: URL) throws -> URL {
        switch url.pathExtension.lowercased() {
        case "csv": return try writeCSV(report, to: url)
        case "json": return try writeJSON(report, to: url)
        default: throw CursorExperimentExportError.unsupportedExtension(url.pathExtension)
        }
    }

    /// Creates the full live export (raw landmark frames plus both replay evaluations).
    /// The caller must run this from a non-interaction export queue.
    public static func writeBundle(_ recording: CursorExperimentRecording, to url: URL) throws -> URL {
        let replay = try CursorExperimentReplayEvaluator.evaluate(recording)
        return try writeJSON(CursorExperimentExportDocument(recording: recording, replay: replay), to: url)
    }

    private static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func number(_ value: CGFloat?) -> String {
        guard let value else { return "" }
        return number(Double(value))
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
