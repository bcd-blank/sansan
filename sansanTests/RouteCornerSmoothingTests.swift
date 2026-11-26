import XCTest
@testable import sansan
import CoreGraphics

final class RouteCornerSmoothingTests: XCTestCase {
    func testSharpCornerGetsFilletSamples() {
        // Right-angle (90°) corner — above 60° threshold.
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 40, y: 0),
            CGPoint(x: 40, y: 40)
        ]
        let smoothed = RouteCornerSmoothing.smoothPoints(
            points,
            radius: 4,
            maxAlong: 10,
            minTurnDegrees: 60,
            samples: 5
        )
        XCTAssertGreaterThan(smoothed.count, points.count, "fillet must insert samples")
        // Apex (40,0) should not remain as a hard tip — first/last preserved.
        XCTAssertEqual(smoothed.first, points.first)
        XCTAssertEqual(smoothed.last, points.last)
        let hasExactApex = smoothed.contains { hypot($0.x - 40, $0.y - 0) < 0.05 }
        XCTAssertFalse(hasExactApex, "exact sharp apex should be replaced by fillet")
    }

    func testGentleTurnUnchanged() {
        // ~20° bend — below threshold.
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 50, y: 0),
            CGPoint(x: 100, y: 18)
        ]
        let smoothed = RouteCornerSmoothing.smoothPoints(
            points,
            radius: 4,
            maxAlong: 10,
            minTurnDegrees: 60,
            samples: 5
        )
        XCTAssertEqual(smoothed.count, points.count)
        XCTAssertEqual(smoothed[1].x, points[1].x, accuracy: 0.01)
        XCTAssertEqual(smoothed[1].y, points[1].y, accuracy: 0.01)
    }

    func testStraightUnchanged() {
        let points: [CGPoint] = (0..<8).map { CGPoint(x: CGFloat($0) * 10, y: 0) }
        let smoothed = RouteCornerSmoothing.smoothPoints(points)
        XCTAssertEqual(smoothed.count, points.count)
    }
}
