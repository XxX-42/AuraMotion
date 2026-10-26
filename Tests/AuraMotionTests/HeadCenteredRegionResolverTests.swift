import XCTest
import CoreGraphics
import simd
@testable import AuraMotionCore

final class HeadCenteredRegionResolverTests: XCTestCase {
    private let bounds = CGRect(x: 100, y: 200, width: 1000, height: 1000)
    private func face(x: Float = 0.5, y: Float = 0.5, time: Double = 10, mirrored: Bool = false) -> FaceSample {
        FaceSample(frameID: 1, timestamp: time, isTimestampEstimated: false, isMirrored: mirrored, landmarks: [],
            headTransform: nil, headPose: HeadPose(yaw: 0, pitch: 0, roll: 0, centerX: x, centerY: y, scale: 0.2),
            leftIrisCenter: nil, rightIrisCenter: nil, confidence: nil)
    }
    private func gaze(_ x: CGFloat, _ y: CGFloat, time: Double = 10) -> GazeEstimate {
        GazeEstimate(screenPoint: CGPoint(x: x, y: y), timestamp: time, direction: nil, confidence: 0.8)
    }
    func testRingsAndExactBoundaries() throws {
        let resolver = HeadCenteredRegionResolver()
        let f = face()
        for (distance, expected) in [(0.0, RadialRegion.center), (80.0, .center), (81.0, .ring1), (200.0, .ring1), (201.0, .ring2), (380.0, .ring2), (381.0, .outside)] {
            let result = try XCTUnwrap(resolver.resolve(face: f, gaze: gaze(600 + distance, 700), displayBounds: bounds, now: 10.01))
            XCTAssertEqual(result.radial, expected, "distance \(distance)")
            if expected == .center || expected == .outside { XCTAssertNil(result.sector) }
        }
    }
    func testEightDirectionsAndNearTheirAxes() throws {
        let resolver = HeadCenteredRegionResolver()
        let sectors: [AngularSector] = [.east, .southEast, .south, .southWest, .west, .northWest, .north, .northEast]
        for i in 0..<8 {
            for offset in [-1.0, 0, 1.0] {
                let angle = (Double(i) * 45 + offset) * .pi / 180
                let sample = gaze(600 + 150*cos(angle), 700 + 150*sin(angle))
                let result = try XCTUnwrap(resolver.resolve(face: face(), gaze: sample, displayBounds: bounds, now: 10.01))
                XCTAssertEqual(result.radial, .ring1)
                XCTAssertEqual(result.sector, sectors[i], "angle \(angle)")
            }
        }
        for (angle, sector) in [(22.4, AngularSector.east), (22.6, .southEast), (337.4, .northEast), (337.6, .east)] {
            let theta = angle * .pi / 180
            XCTAssertEqual(resolver.resolve(face: face(), gaze: gaze(600 + 150*cos(theta), 700 + 150*sin(theta)), displayBounds: bounds, now: 10.01)?.sector, sector)
        }
    }
    func testHeadMotionAndMirroring() throws {
        let resolver = HeadCenteredRegionResolver()
        let sample = gaze(750, 700)
        XCTAssertEqual(resolver.resolve(face: face(), gaze: sample, displayBounds: bounds, now: 10.01)?.sector, .east)
        XCTAssertEqual(resolver.resolve(face: face(x: 0.8), gaze: sample, displayBounds: bounds, now: 10.01)?.sector, .west)
        let projected = try XCTUnwrap(HeadReferenceProjector.debugApproximation(pose: try XCTUnwrap(face(x: 0.25).headPose), isMirrored: true, displayBounds: bounds))
        XCTAssertEqual(projected.x, 850, accuracy: 0.001)
    }
    func testTimeGateAndStaleInput() {
        let resolver = HeadCenteredRegionResolver()
        XCTAssertNotNil(resolver.resolve(face: face(time: 10), gaze: gaze(750, 700, time: 10.079), displayBounds: bounds, now: 10.1))
        XCTAssertNil(resolver.resolve(face: face(time: 10), gaze: gaze(750, 700, time: 10.081), displayBounds: bounds, now: 10.1))
        XCTAssertNil(resolver.resolve(face: face(), gaze: gaze(750, 700), displayBounds: bounds, now: 10.301))
        XCTAssertNil(resolver.resolve(face: face(), gaze: gaze(750, 700), displayBounds: bounds, now: 9.99))
    }
    func testExistingFixationDetectorDrivesCommit() {
        var detector = FixationDetector()
        var tracker = HeadCenteredTargeting()
        for (time, expectedFocused) in [(10.0, false), (10.08, false), (10.14, true)] {
            let sample = gaze(750, 700, time: time)
            let fixation = detector.update(sample)
            tracker.update(face: face(time: time), gaze: sample, fixation: fixation, displayBounds: bounds, now: time + 0.01)
            XCTAssertEqual(tracker.focused != nil, expectedFocused)
        }
        XCTAssertEqual(tracker.focused?.sector, .east)
    }

    func testCandidateDoesNotCommitAndFocusExpires() {
        var tracker = HeadCenteredTargeting()
        let right = CGPoint(x: 750, y: 700), up = CGPoint(x: 600, y: 550)
        tracker.update(face: face(), gaze: gaze(right.x, right.y), fixation: .candidate(right), displayBounds: bounds, now: 10.01)
        XCTAssertNil(tracker.focused)
        XCTAssertEqual(tracker.candidate?.sector, .east)
        tracker.update(face: face(), gaze: gaze(right.x, right.y), fixation: .focused(right), displayBounds: bounds, now: 10.02)
        XCTAssertEqual(tracker.focused?.sector, .east)
        tracker.update(face: face(time: 10.1), gaze: gaze(up.x, up.y, time: 10.1), fixation: .candidate(up), displayBounds: bounds, now: 10.11)
        XCTAssertEqual(tracker.focused?.sector, .east)
        XCTAssertEqual(tracker.candidate?.sector, .north)
        tracker.update(face: nil, gaze: nil, fixation: .unavailable, displayBounds: bounds, now: 10.31)
        XCTAssertNil(tracker.focused)
        XCTAssertNil(tracker.candidate)
        XCTAssertEqual(tracker.diagnostics.switchCount, 1)
    }
}
