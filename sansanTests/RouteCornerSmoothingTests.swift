import XCTest
@testable import sansan
import CoreGraphics
import CoreLocation
import MapKit

final class RouteCornerSmoothingTests: XCTestCase {
    func testSharpCornerGetsFilletSamples() {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 40, y: 0),
            CGPoint(x: 40, y: 40)
        ]
        let smoothed = RouteCornerSmoothing.smoothPoints(
            points,
            radius: 12,
            maxAlong: 12,
            minTurnDegrees: 30,
            samples: 8
        )
        XCTAssertGreaterThan(smoothed.count, points.count, "fillet must insert samples")
        XCTAssertEqual(smoothed.first, points.first)
        XCTAssertEqual(smoothed.last, points.last)
        let hasExactApex = smoothed.contains { hypot($0.x - 40, $0.y - 0) < 0.05 }
        XCTAssertFalse(hasExactApex, "exact sharp apex should be replaced by fillet")
    }

    /// curve3-class ~42° adjacent elbow must fillet under 30° threshold.
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
        let minDist = smoothed.dropFirst().dropLast().map { hypot($0.x - apex.x, $0.y - apex.y) }.min() ?? 0
        XCTAssertGreaterThan(minDist, 1.0, "circular fillet must leave the apex")
    }

    /// Compound zigzags: each ≥30° elbow rounds locally; path topology preserved
    /// (no single extended-arm chord that deletes mid vertices).
    func testCompoundTipRoundsLocallyWithoutRewritingPath() {
        var points: [CGPoint] = [CGPoint(x: 0, y: 0)]
        points.append(CGPoint(x: 40, y: 0))
        points.append(CGPoint(x: 46, y: 2))
        points.append(CGPoint(x: 50, y: 0)) // tip
        points.append(CGPoint(x: 54, y: 6))
        points.append(CGPoint(x: 70, y: 28))
        let tip = points[3]
        let smoothed = RouteCornerSmoothing.smoothPoints(
            points,
            radius: 12,
            maxAlong: 12,
            minTurnDegrees: 30,
            samples: 8
        )
        XCTAssertGreaterThan(smoothed.count, 2)
        // Endpoints + far legs preserved.
        XCTAssertEqual(smoothed.first, points.first)
        XCTAssertEqual(smoothed.last, points.last)
        // Tip vertex itself should be replaced (rounded).
        let hasExactTip = smoothed.contains { hypot($0.x - tip.x, $0.y - tip.y) < 0.2 }
        XCTAssertFalse(hasExactTip, "sharp tip vertex must be rounded away")
        // Path must still pass near the tip (slight round, not a distant chord).
        let minDist = smoothed.map { hypot($0.x - tip.x, $0.y - tip.y) }.min() ?? 999
        XCTAssertLessThan(minDist, 10, "local fillet must stay near tip; got \(minDist)")
    }

    func testGentleTurnUnchanged() {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 50, y: 0),
            CGPoint(x: 100, y: 13)
        ]
        let smoothed = RouteCornerSmoothing.smoothPoints(
            points,
            radius: 12,
            maxAlong: 12,
            minTurnDegrees: 30,
            samples: 8
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

    /// Same input array: sharp-disabled path equals raw; smoothed only differs near ≥30° elbows.
    func testGamajiSameInputPreservesPathOutsideFillets() {
        let fixture = UITestMountainPathFixtures.gamajicheon
        let coords: [CLLocationCoordinate2D] = fixture.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        XCTAssertGreaterThanOrEqual(coords.count, 240)
        let apexIdx = 232
        let apex = coords[apexIdx]
        XCTAssertEqual(apex.latitude, 37.64200773, accuracy: 1e-7)
        XCTAssertEqual(apex.longitude, 126.63898472, accuracy: 1e-7)

        // Force-enabled smooth (tests run with smoothing on by default).
        let smoothed = RouteCornerSmoothing.smoothCoordinates(coords)
        XCTAssertGreaterThan(smoothed.count, 2)

        // Every raw vertex with adjacent turn <30° must still appear (within 0.15m).
        var preserved = 0
        var filletedAway = 0
        for i in 1..<(coords.count - 1) {
            let a = coords[i - 1], b = coords[i], c = coords[i + 1]
            let turn = Self.turnDegrees(a, b, c)
            let bLoc = CLLocation(latitude: b.latitude, longitude: b.longitude)
            let nearest = smoothed.map {
                bLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
            }.min() ?? 999
            if turn + 1e-3 < 30 {
                XCTAssertLessThan(
                    nearest,
                    0.15,
                    "sub-threshold vertex \(i) turn=\(turn) must be preserved; nearest=\(nearest)m"
                )
                preserved += 1
            } else if nearest > 0.5 {
                filletedAway += 1
            }
        }
        XCTAssertGreaterThan(preserved, 100, "most vertices are gentle and must match")
        XCTAssertGreaterThan(filletedAway, 0, "at least one ≥30° tip should be rounded away")

        // Apex cut is slight (local), not a multi-meter chord rewrite.
        let apexLoc = CLLocation(latitude: apex.latitude, longitude: apex.longitude)
        let minCut = smoothed.map {
            apexLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? 0
        XCTAssertGreaterThan(minCut, 0.3, "curve3 apex should leave the tip slightly; got \(minCut)m")
        XCTAssertLessThan(minCut, 4.5, "apex cut must stay within short-arc budget; got \(minCut)m")
        print("CURVE3_V2E preserved=\(preserved) filletedAway=\(filletedAway) minCut=\(minCut)")
    }

    func testGamajiFilletThenStretchStillLocal() {
        let fixture = UITestMountainPathFixtures.gamajicheon
        let coords: [CLLocationCoordinate2D] = fixture.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        let apex = coords[232]
        let apexLoc = CLLocation(latitude: apex.latitude, longitude: apex.longitude)
        let filleted = RouteCornerSmoothing.smoothCoordinates(coords)
        let stretches = RouteSelfCrossing.chronologicalCoordinateStretches(in: filleted)
        let list = stretches.isEmpty ? [filleted] : stretches
        let all = list.flatMap { $0 }
        let minCut = all.map {
            apexLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? 0
        XCTAssertGreaterThan(minCut, 0.3)
        XCTAssertLessThan(minCut, 4.5)
    }

    private static func turnDegrees(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D,
        _ c: CLLocationCoordinate2D
    ) -> Double {
        let ab = MKMapPoint(b).x - MKMapPoint(a).x
        let aby = MKMapPoint(b).y - MKMapPoint(a).y
        let bc = MKMapPoint(c).x - MKMapPoint(b).x
        let bcy = MKMapPoint(c).y - MKMapPoint(b).y
        let abLen = hypot(ab, aby), bcLen = hypot(bc, bcy)
        guard abLen > 1e-12, bcLen > 1e-12 else { return 0 }
        let dot = max(-1, min(1, (ab * bc + aby * bcy) / (abLen * bcLen)))
        return acos(dot) * 180 / .pi
    }
}
