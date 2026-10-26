import XCTest
import CoreGraphics
@testable import AuraMotionCore

final class MotionPriorityTests: XCTestCase {
    func testBaselinePolicyAndRuntimeUnload() {
        let arbitrator = InputArbitrator()
        XCTAssertFalse(arbitrator.isMotionPriorityEnabled)
        XCTAssertTrue(InputArbitrator.shouldArbitrate(.leftMouseDown, motionPriorityEnabled: false))
        XCTAssertFalse(InputArbitrator.shouldArbitrate(.mouseMoved, motionPriorityEnabled: false))
        arbitrator.setMotionPriorityEnabled(true)
        XCTAssertTrue(arbitrator.isMotionPriorityEnabled)
        for type: CGEventType in [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel, .otherMouseDown] {
            XCTAssertTrue(InputArbitrator.shouldArbitrate(type, motionPriorityEnabled: arbitrator.isMotionPriorityEnabled))
        }
        arbitrator.setMotionPriorityEnabled(false)
        XCTAssertFalse(arbitrator.isMotionPriorityEnabled)
        XCTAssertFalse(InputArbitrator.shouldArbitrate(.scrollWheel, motionPriorityEnabled: arbitrator.isMotionPriorityEnabled))
        XCTAssertFalse(InputArbitrator.shouldArbitrate(.keyDown, motionPriorityEnabled: true))
        XCTAssertEqual(arbitrator.currentEpoch(), 1, "Policy updates do not alter the output arbitration epoch")
    }
}
