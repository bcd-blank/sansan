import XCTest
@testable import sansan
import CoreGraphics

final class RouteSelfCrossingTests: XCTestCase {
    /// Gentle dense curve — consecutive edges near casing width must not false-hit.
    func testDenseCurveProducesNoProximityHits() {
        var points: [CGPoint] = []
        let n = 40
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            let angle = t * .pi * 0.55
            points.append(CGPoint(x: cos(angle) * 120, y: sin(angle) * 120))
        }
        let hits = RouteSelfCrossing.hits(
            in: points,
            minLoopLength: 40,
            minSeparationEdges: 2,
            minCrossSin: 0.20,
            minProximitySin: 0.28,
            dedupeDistance: 8,
            proximityDistance: 5
        )
        XCTAssertTrue(hits.isEmpty, "dense curve joints must not paint white bridges: \(hits)")
    }

    /// True X: non-adjacent interior crossing with high |sin|.
    func testTrueXKeepsHardIntersection() {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 40, y: 0),
            CGPoint(x: 80, y: 0),
            CGPoint(x: 120, y: 0),
            CGPoint(x: 120, y: 40),
            CGPoint(x: 80, y: 80),
            CGPoint(x: 40, y: 40),
            CGPoint(x: 40, y: -20),
            CGPoint(x: 40, y: -60)
        ]
        // Edge (0→1) horizontal; later edge near (5→6) crosses earlier vertical-ish path.
        // Clearer X: A across, then later B across A.
        let xPoints: [CGPoint] = [
            CGPoint(x: 0, y: 50),
            CGPoint(x: 100, y: 50),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 150, y: 100),
            CGPoint(x: 150, y: 0),
            CGPoint(x: 50, y: 0),
            CGPoint(x: 50, y: 100)
        ]
        let hits = RouteSelfCrossing.hits(
            in: xPoints,
            minLoopLength: 30,
            minSeparationEdges: 2,
            minCrossSin: 0.20,
            minProximitySin: 0.28,
            dedupeDistance: 8,
            proximityDistance: 0
        )
        XCTAssertFalse(hits.isEmpty, "true X must remain a hit")
    }

    /// Shallow parallel approach with |sin| ≥ 0.28 and interior params → proximity hit.
    func testShallowParallelProximityKept() {
        // Two nearly parallel diagonals (~16°), gap 3pt, non-adjacent.
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 20),
            CGPoint(x: 140, y: 80),
            CGPoint(x: 160, y: 140),
            CGPoint(x: 10, y: 8),
            CGPoint(x: 110, y: 28)
        ]
        let hits = RouteSelfCrossing.hits(
            in: points,
            minLoopLength: 20,
            minSeparationEdges: 2,
            minCrossSin: 0.20,
            minProximitySin: 0.28,
            dedupeDistance: 8,
            proximityDistance: 6
        )
        XCTAssertFalse(hits.isEmpty, "shallow parallel proximity (≥12°) must keep a hit: \(hits)")
    }
}
