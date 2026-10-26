import Foundation
import CoreMedia

/// SampleCarrier holds a CMSampleBuffer for pipeline transport.
///
/// Invariant: The wrapped CMSampleBuffer is immutable after creation and
/// remains immutable while hand and face workers independently retain it.
public final class SampleCarrier: @unchecked Sendable {
    public let frameID: UInt64
    public let buffer: CMSampleBuffer
    public let hostPresentationTime: TimeInterval
    public let isEstimatedTime: Bool

    public init(buffer: CMSampleBuffer, hostPresentationTime: TimeInterval, isEstimatedTime: Bool, frameID: UInt64 = 0) {
        self.frameID = frameID
        self.buffer = buffer
        self.hostPresentationTime = hostPresentationTime
        self.isEstimatedTime = isEstimatedTime
    }
}
