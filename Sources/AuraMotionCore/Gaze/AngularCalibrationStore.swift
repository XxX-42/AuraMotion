import Foundation

/// Compatibility metadata only; no frames, landmarks or per-target observations.
public struct AngularCalibrationContext: Codable, Equatable, Sendable {
    public let modelSignature: String
    public let cameraID: String
    public let width: Int, height: Int
    public let mirrored: Bool
    public let displayID: UInt32
    public let displayX: Double, displayY: Double, displayWidth: Double, displayHeight: Double
    public let geometry: DebugScreenGeometry
    public init(modelSignature: String, cameraID: String, width: Int, height: Int, mirrored: Bool,
                displayID: UInt32, displayX: Double, displayY: Double, displayWidth: Double, displayHeight: Double,
                geometry: DebugScreenGeometry) {
        self.modelSignature = modelSignature; self.cameraID = cameraID; self.width = width; self.height = height
        self.mirrored = mirrored; self.displayID = displayID; self.displayX = displayX; self.displayY = displayY
        self.displayWidth = displayWidth; self.displayHeight = displayHeight; self.geometry = geometry
    }
    public var isValid: Bool {
        !modelSignature.isEmpty && !cameraID.isEmpty && width > 0 && height > 0 &&
        [displayX, displayY, displayWidth, displayHeight].allSatisfy(\.isFinite) &&
        displayWidth > 0 && displayHeight > 0 && geometry.valid
    }
}
public struct AngularCalibrationStore {
    private struct Record: Codable { let version: Int; let context: AngularCalibrationContext; let model: AngularGazeCalibration }
    private let defaults: UserDefaults
    private let key = "experimental.angularGazeCalibration.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    @discardableResult public func save(_ model: AngularGazeCalibration, context: AngularCalibrationContext) -> Bool {
        guard context.isValid, model.isValid, context.geometry == model.geometry,
              let data = try? JSONEncoder().encode(Record(version: 1, context: context, model: model)) else { return false }
        defaults.set(data, forKey: key); return true
    }
    public func load(matching context: AngularCalibrationContext) -> AngularGazeCalibration? {
        guard context.isValid, let data = defaults.data(forKey: key),
              let record = try? JSONDecoder().decode(Record.self, from: data), record.version == 1,
              record.context == context, record.model.geometry == context.geometry, record.model.isValid else { return nil }
        return record.model
    }
}
