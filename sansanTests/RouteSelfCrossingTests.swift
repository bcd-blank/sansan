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

    /// Mid-loop cut between earlier/later edges → ≥2 stretches; cut stays away from both edges.
    func testChronologicalStretchesSplitBetweenCross() {
        // Horizontal mid-segment at y=50 (no vertex at x=50), long detour, then vertical
        // through (50,50) so the X is interior on both edges.
        var denseX: [CGPoint] = [
            CGPoint(x: 0, y: 50), CGPoint(x: 25, y: 50), CGPoint(x: 40, y: 50),
            CGPoint(x: 60, y: 50), CGPoint(x: 80, y: 50), CGPoint(x: 100, y: 50),
            CGPoint(x: 120, y: 50)
        ]
        for i in 1...8 { denseX.append(CGPoint(x: 120, y: 50 + CGFloat(i) * 10)) }
        for i in 1...12 { denseX.append(CGPoint(x: 120 - CGFloat(i) * 10, y: 130)) }
        for i in 1...13 { denseX.append(CGPoint(x: 0, y: 130 - CGFloat(i) * 10)) }
        denseX.append(contentsOf: [
            CGPoint(x: 10, y: 0), CGPoint(x: 25, y: 0), CGPoint(x: 40, y: 0),
            CGPoint(x: 50, y: 0),
            CGPoint(x: 50, y: 20), CGPoint(x: 50, y: 35), CGPoint(x: 50, y: 45),
            CGPoint(x: 50, y: 55), CGPoint(x: 50, y: 70), CGPoint(x: 50, y: 90),
            CGPoint(x: 50, y: 110)
        ])

        let hits = RouteSelfCrossing.hits(
            in: denseX,
            minLoopLength: 40,
            minSeparationEdges: 2,
            minCrossSin: 0.20,
            minProximitySin: 0.28,
            dedupeDistance: 8,
            proximityDistance: 0
        )
        XCTAssertFalse(hits.isEmpty, "dense X must hit: \(hits)")
        let stretches = RouteSelfCrossing.chronologicalPointStretches(
            points: denseX,
            hits: hits,
            overlapVertices: 3
        )
        XCTAssertGreaterThanOrEqual(
            stretches.count, 2,
            "self-cross must split into ≥2 stretches: \(stretches.count) hits=\(hits)"
        )
        let cuts = RouteSelfCrossing.stretchCutIndices(hits: hits, lastIndex: denseX.count - 1)
        XCTAssertFalse(cuts.isEmpty, "expected mid-loop cut; hits=\(hits)")
        for hit in hits where hit.laterEdge - hit.earlierEdge >= 8 {
            let matching = cuts.filter { $0 > hit.earlierEdge && $0 < hit.laterEdge }
            XCTAssertFalse(
                matching.isEmpty,
                "cut must lie between earlier=\(hit.earlierEdge) and later=\(hit.laterEdge); cuts=\(cuts)"
            )
        }
    }

    /// No hits → single continuous stretch (no dashed chops).
    func testNoHitsYieldsSingleStretch() {
        let points: [CGPoint] = (0..<20).map { CGPoint(x: CGFloat($0) * 10, y: 0) }
        let stretches = RouteSelfCrossing.chronologicalPointStretches(
            points: points,
            hits: [],
            overlapVertices: 4
        )
        XCTAssertEqual(stretches.count, 1)
        XCTAssertEqual(stretches[0].count, points.count)
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
