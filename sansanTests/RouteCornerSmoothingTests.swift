import XCTest
@testable import sansan
import CoreGraphics

final class RouteCornerSmoothingTests: XCTestCase {
    func testSharpCornerGetsFilletSamples() {
        // Right-angle (90°) corner — above 30° threshold.
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 40, y: 0),
            CGPoint(x: 40, y: 40)
        ]
        let smoothed = RouteCornerSmoothing.smoothPoints(
            points,
            radius: 12,
            maxAlong: 28,
            minTurnDegrees: 30,
            samples: 6
        )
        XCTAssertGreaterThan(smoothed.count, points.count, "fillet must insert samples")
        // Apex (40,0) should not remain as a hard tip — first/last preserved.
        XCTAssertEqual(smoothed.first, points.first)
        XCTAssertEqual(smoothed.last, points.last)
        let hasExactApex = smoothed.contains { hypot($0.x - 40, $0.y - 0) < 0.05 }
        XCTAssertFalse(hasExactApex, "exact sharp apex should be replaced by fillet")
    }

    /// curve3-class ~42° adjacent elbow must fillet under v2 30° threshold.
    func testMidSharpFortyDegreeFillet() {
        let rad = CGFloat.pi * 40 / 180
        let apex = CGPoint(x: 50, y: 0)
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            apex,
            CGPoint(x: 50 + 50 * cos(rad), y: 50 * sin(rad))
        ]
        let smoothed = RouteCornerSmoothing.smoothPoints(points)
        XCTAssertGreaterThan(smoothed.count, points.count, "≈40° must fillet at minTurn=30")
        // Circular fillet must cut the tip — nearest sample inset from apex.
        let minDist = smoothed.dropFirst().dropLast().map { hypot($0.x - apex.x, $0.y - apex.y) }.min() ?? 0
        XCTAssertGreaterThan(minDist, 2.0, "circular fillet must visibly leave the apex")
    }

    func testGentleTurnUnchanged() {
        // ~15° bend — below 30° threshold.
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 50, y: 0),
            CGPoint(x: 100, y: 13)
        ]
        let smoothed = RouteCornerSmoothing.smoothPoints(
            points,
            radius: 12,
            maxAlong: 28,
            minTurnDegrees: 30,
            samples: 6
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
