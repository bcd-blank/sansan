import XCTest
@testable import sansan
import CoreGraphics
import CoreLocation
import MapKit
import UIKit

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

    /// Optimized hits() must match nested-pathLength legacy bit-for-bit on fixtures.
    func testOptimizedHitsMatchLegacyOnSyntheticCases() {
        let cases: [[CGPoint]] = [
            (0..<40).map { i in
                let t = CGFloat(i) / 40
                let angle = t * .pi * 0.55
                return CGPoint(x: cos(angle) * 120, y: sin(angle) * 120)
            },
            [
                CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50), CGPoint(x: 100, y: 100),
                CGPoint(x: 150, y: 100), CGPoint(x: 150, y: 0), CGPoint(x: 50, y: 0),
                CGPoint(x: 50, y: 100)
            ],
            [
                CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 20), CGPoint(x: 140, y: 80),
                CGPoint(x: 160, y: 140), CGPoint(x: 10, y: 8), CGPoint(x: 110, y: 28)
            ]
        ]
        for (idx, points) in cases.enumerated() {
            assertHitsIdentical(
                points,
                minLoop: 30,
                sep: 2,
                proximity: idx == 2 ? 6 : 0,
                label: "synthetic-\(idx)"
            )
        }
    }

    /// Real device backup (no seed): all records — optimized ≡ no-AABB (bbox safe) and
    /// nested-pathLength legacy on every route with cleaned n≤900; longest included.
    func testOptimizedHitsMatchLegacyOnRealBackupRecords() throws {
        let backupURL = URL(
            fileURLWithPath:
                "/Users/jeongwook/Documents/sansan-보관/기기백업/ios-container-황금해안길-20261127-121238/container/Documents/users/local/records.json"
        )
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw XCTSkip("real backup missing at \(backupURL.path)")
        }
        let data = try Data(contentsOf: backupURL)
        let records = try JSONDecoder.hikingConnectivity.decode([SavedHikingSession].self, from: data)
        XCTAssertFalse(records.isEmpty, "backup must contain real records")
        let sorted = records.sorted { $0.session.points.count > $1.session.points.count }
        XCTAssertGreaterThanOrEqual(
            sorted.first?.session.points.count ?? 0, 3000,
            "expected longest real route (≥3000 pts) in backup"
        )
        var comparedNoAABB = 0
        var comparedNested = 0
        var maxPts = 0
        var longestLabel = ""
        for record in sorted {
            let coords = record.session.points.map(\.coordinate)
            guard coords.count >= 5 else { continue }
            let mapPoints = coords.map { MKMapPoint($0) }
            let raw = mapPoints.map { CGPoint(x: $0.x, y: $0.y) }
            let points = RouteSelfCrossing.cleanedPoints(raw)
            guard points.count >= 5 else { continue }
            let mid = coords[coords.count / 2]
            let mpp = MKMetersPerMapPointAtLatitude(mid.latitude)
            let minLoop = CGFloat(60 / max(mpp, 1e-9))
            let dedupe = CGFloat(12 / max(mpp, 1e-9))
            let proximity = CGFloat(8 / max(mpp, 1e-9))
            let name = record.displayName ?? record.id.uuidString
            let label = "\(name) pts=\(points.count)"
            // All records (incl. longest): optimized vs d[]+acc without AABB → bbox is neutral.
            assertHitListsEqual(
                RouteSelfCrossing.hits(
                    in: points,
                    minLoopLength: minLoop,
                    minSeparationEdges: 2,
                    minCrossSin: 0.18,
                    dedupeDistance: dedupe,
                    proximityDistance: proximity
                ),
                RouteSelfCrossing.hitsWithoutAABBSkip(
                    in: points,
                    minLoopLength: minLoop,
                    minSeparationEdges: 2,
                    minCrossSin: 0.18,
                    dedupeDistance: dedupe,
                    proximityDistance: proximity
                ),
                label: "\(label) bbox"
            )
            comparedNoAABB += 1
            // Nested pathLength legacy — O(n³); keep for mid-size routes only.
            if points.count <= 900 {
                assertHitListsEqual(
                    RouteSelfCrossing.hits(
                        in: points,
                        minLoopLength: minLoop,
                        minSeparationEdges: 2,
                        minCrossSin: 0.18,
                        dedupeDistance: dedupe,
                        proximityDistance: proximity
                    ),
                    RouteSelfCrossing.hitsLegacyNestedPathLength(
                        in: points,
                        minLoopLength: minLoop,
                        minSeparationEdges: 2,
                        minCrossSin: 0.18,
                        dedupeDistance: dedupe,
                        proximityDistance: proximity
                    ),
                    label: "\(label) nested"
                )
                comparedNested += 1
            }
            if points.count > maxPts {
                maxPts = points.count
                longestLabel = label
                // Accumulators match pathLength (same sum order — never cum[j]-cum[i]).
                assertAccumulatedLengthsMatchPathLength(points, label: label)
            }
        }
        XCTAssertGreaterThan(comparedNoAABB, 0)
        XCTAssertGreaterThan(comparedNested, 0)
        print(
            "[selfcross-parity] all=\(comparedNoAABB) nested≤900=\(comparedNested) maxPts=\(maxPts) longest=\(longestLabel) diff=0"
        )
    }

    private func assertHitsIdentical(
        _ points: [CGPoint],
        minLoop: CGFloat,
        sep: Int,
        minCrossSin: CGFloat = 0.20,
        proximity: CGFloat,
        dedupe: CGFloat = 8,
        label: String
    ) {
        assertHitListsEqual(
            RouteSelfCrossing.hits(
                in: points,
                minLoopLength: minLoop,
                minSeparationEdges: sep,
                minCrossSin: minCrossSin,
                minProximitySin: 0.28,
                dedupeDistance: dedupe,
                proximityDistance: proximity
            ),
            RouteSelfCrossing.hitsLegacyNestedPathLength(
                in: points,
                minLoopLength: minLoop,
                minSeparationEdges: sep,
                minCrossSin: minCrossSin,
                minProximitySin: 0.28,
                dedupeDistance: dedupe,
                proximityDistance: proximity
            ),
            label: label
        )
    }

    private func assertHitListsEqual(
        _ optimized: [RouteSelfCrossing.Hit],
        _ reference: [RouteSelfCrossing.Hit],
        label: String
    ) {
        XCTAssertEqual(
            optimized.count, reference.count,
            "\(label): hit count \(optimized.count) vs ref \(reference.count)"
        )
        for (i, pair) in zip(optimized, reference).enumerated() {
            XCTAssertEqual(pair.0.earlierEdge, pair.1.earlierEdge, "\(label)[\(i)].earlierEdge")
            XCTAssertEqual(pair.0.laterEdge, pair.1.laterEdge, "\(label)[\(i)].laterEdge")
            XCTAssertEqual(pair.0.u, pair.1.u, accuracy: 0, "\(label)[\(i)].u")
            XCTAssertEqual(pair.0.point.x, pair.1.point.x, accuracy: 0, "\(label)[\(i)].x")
            XCTAssertEqual(pair.0.point.y, pair.1.point.y, accuracy: 0, "\(label)[\(i)].y")
        }
    }

    /// Route stroke mask: optimized hits vs nested legacy → pixel diff 0 (light canvas).
    func testRouteStrokeMaskPixelDiffZeroOnHwanggeumhaean() throws {
        let backupURL = URL(
            fileURLWithPath:
                "/Users/jeongwook/Documents/sansan-보관/기기백업/ios-container-황금해안길-20261127-121238/container/Documents/users/local/records.json"
        )
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw XCTSkip("real backup missing")
        }
        let records = try JSONDecoder.hikingConnectivity.decode(
            [SavedHikingSession].self,
            from: Data(contentsOf: backupURL)
        )
        guard let record = records.first(where: { ($0.displayName ?? "") == "황금해안길" })
                ?? records.first(where: { $0.session.points.count >= 3000 }) else {
            throw XCTSkip("황금해안길 / long route missing")
        }
        let coords = record.session.points.map(\.coordinate)
        let canvas = CGSize(width: 390, height: 420)
        let region = HikingMapRegion.fitting(coordinates: coords, viewSize: canvas)
        let points: [CGPoint] = coords.map {
            HikingMapRegion.point(for: $0, in: region, canvasSize: canvas)
        }
        let cleaned = RouteSelfCrossing.cleanedPoints(points)
        let minLoop: CGFloat = 48
        let casing: CGFloat = 9
        let optHits = RouteSelfCrossing.hits(
            in: cleaned,
            minLoopLength: minLoop,
            minSeparationEdges: 2,
            minCrossSin: 0.20,
            dedupeDistance: max(casing * 2, minLoop * 0.2),
            proximityDistance: casing * 0.65
        )
        let legHits = RouteSelfCrossing.hitsLegacyNestedPathLength(
            in: cleaned,
            minLoopLength: minLoop,
            minSeparationEdges: 2,
            minCrossSin: 0.20,
            dedupeDistance: max(casing * 2, minLoop * 0.2),
            proximityDistance: casing * 0.65
        )
        XCTAssertEqual(optHits, legHits)
        let optStretches = RouteSelfCrossing.chronologicalPointStretches(
            points: cleaned, hits: optHits, overlapVertices: 4
        )
        let legStretches = RouteSelfCrossing.chronologicalPointStretches(
            points: cleaned, hits: legHits, overlapVertices: 4
        )
        XCTAssertEqual(optStretches.count, legStretches.count)
        let optMask = Self.renderStrokeMask(stretches: optStretches, canvas: canvas, lineWidth: 5)
        let legMask = Self.renderStrokeMask(stretches: legStretches, canvas: canvas, lineWidth: 5)
        XCTAssertEqual(optMask.pngData(), legMask.pngData(), "route stroke mask pixel diff must be 0")
    }

    private static func renderStrokeMask(
        stretches: [[CGPoint]],
        canvas: CGSize,
        lineWidth: CGFloat
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))
            UIColor.white.setStroke()
            for stretch in stretches where stretch.count >= 2 {
                let path = UIBezierPath()
                path.lineWidth = lineWidth
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.move(to: stretch[0])
                for p in stretch.dropFirst() { path.addLine(to: p) }
                path.stroke()
            }
        }
    }

    /// d[] + acc += d[j-1] must equal nested pathLength for sampled (i,j) on the longest route.
    private func assertAccumulatedLengthsMatchPathLength(_ points: [CGPoint], label: String) {
        let lastEdge = points.count - 2
        var d = [CGFloat](repeating: 0, count: lastEdge + 1)
        for k in 0...lastEdge {
            let a = points[k], b = points[k + 1]
            d[k] = hypot(b.x - a.x, b.y - a.y)
        }
        let step = max(1, lastEdge / 40)
        for i in stride(from: 0, through: lastEdge, by: step) {
            var acc: CGFloat = 0
            for j in (i + 1)...lastEdge {
                acc += d[j - 1]
                if (j - i) % step != 0, j != lastEdge { continue }
                var nested: CGFloat = 0
                for index in i..<j {
                    nested += hypot(
                        points[index + 1].x - points[index].x,
                        points[index + 1].y - points[index].y
                    )
                }
                XCTAssertEqual(acc, nested, accuracy: 0, "\(label) acc≠pathLength i=\(i) j=\(j)")
            }
        }
    }
}
