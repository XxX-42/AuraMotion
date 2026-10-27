import XCTest
@testable import AuraMotionCore

final class GazeSpotlightGeometryTests: XCTestCase {
    func testCircleAndOpacityValues() throws {
        let frame = try XCTUnwrap(GazeSpotlightGeometry.circle(center: CGPoint(x: 150, y: 250)))
        XCTAssertEqual(frame.width, 1000); XCTAssertEqual(frame.height, 1000)
        XCTAssertEqual(frame.midX, 150); XCTAssertEqual(frame.midY, 250)
        XCTAssertEqual(GazeSpotlightGeometry.highlightOpacity, 0.05)
        XCTAssertEqual(GazeSpotlightGeometry.dimOpacity, 0.20)
    }
    func testInvalidPointRejected() {
        XCTAssertNil(GazeSpotlightGeometry.circle(center: CGPoint(x: CGFloat.nan, y: 0)))
    }
}

extension GazeSpotlightGeometryTests {
    func testLargestOverlapForFourQuadrantsAndMidpointTies() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let cases: [(CGPoint, ScreenQuadrant)] = [
            (CGPoint(x: 100, y: 800), .topLeft), (CGPoint(x: 1300, y: 800), .topRight),
            (CGPoint(x: 100, y: 100), .bottomLeft), (CGPoint(x: 1300, y: 100), .bottomRight),
            (CGPoint(x: 719, y: 451), .topLeft), (CGPoint(x: 721, y: 449), .bottomRight)
        ]
        for (center, expected) in cases {
            XCTAssertEqual(GazeSpotlightGeometry.largestOverlapQuadrant(center: center, screen: screen), expected)
        }
        XCTAssertEqual(GazeSpotlightGeometry.largestOverlapQuadrant(center: CGPoint(x: 720, y: 450), screen: screen, previous: .bottomRight), .bottomRight)
        XCTAssertEqual(GazeSpotlightGeometry.largestOverlapQuadrant(center: CGPoint(x: 720, y: 450), screen: screen), .topLeft)
        XCTAssertNil(GazeSpotlightGeometry.largestOverlapQuadrant(center: CGPoint(x: -1, y: 0), screen: screen))
    }
    func testSelectedQuadrantHasMaximumSampledCircleOverlap() throws {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let quadrants: [ScreenQuadrant] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        for center in [CGPoint(x: 200,y: 200), CGPoint(x: 710,y: 460), CGPoint(x: 1200,y: 800)] {
            let selected = try XCTUnwrap(GazeSpotlightGeometry.largestOverlapQuadrant(center: center, screen: screen))
            func sampledArea(_ quadrant: ScreenQuadrant) -> Int {
                let rect = GazeSpotlightGeometry.quadrantRect(quadrant, screen: screen)
                var count = 0
                for i in 0..<120 { for j in 0..<120 {
                    let x = rect.minX + (CGFloat(i) + 0.5) * rect.width / 120
                    let y = rect.minY + (CGFloat(j) + 0.5) * rect.height / 120
                    if hypot(x-center.x, y-center.y) <= GazeSpotlightGeometry.radius { count += 1 }
                } }
                return count
            }
            let selectedArea = sampledArea(selected)
            for quadrant in quadrants { XCTAssertGreaterThanOrEqual(selectedArea, sampledArea(quadrant)) }
        }
    }
}
