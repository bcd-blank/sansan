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
        let smoothed = RouteCornerSmoothing.smoothPoints(points)
        XCTAssertGreaterThan(smoothed.count, points.count)
        XCTAssertEqual(smoothed.first, points.first)
        XCTAssertEqual(smoothed.last, points.last)
        let hasExactApex = smoothed.contains { hypot($0.x - 40, $0.y - 0) < 0.05 }
        XCTAssertFalse(hasExactApex)
    }

    func testGentleTurnUnchanged() {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 50, y: 0),
            CGPoint(x: 100, y: 13)
        ]
        XCTAssertEqual(RouteCornerSmoothing.smoothPoints(points).count, points.count)
    }

    func testStraightUnchanged() {
        let points: [CGPoint] = (0..<8).map { CGPoint(x: CGFloat($0) * 10, y: 0) }
        XCTAssertEqual(RouteCornerSmoothing.smoothPoints(points).count, points.count)
    }

    /// Micro-jog ≥30° but low protrusion must stay raw (no tipzoom teeth).
    func testLowProtrusionMicroJogNotFilleted() {
        // Shallow 35° bump with tiny protrusion over a long chord.
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 40, y: 0),
            CGPoint(x: 42, y: 1.2), // micro jog
            CGPoint(x: 44, y: 0),
            CGPoint(x: 80, y: 0)
        ]
        let jog = points[2]
        let smoothed = RouteCornerSmoothing.smoothPoints(
            points,
            minTipProtrusion: 8,
            tipChordSpan: 36
        )
        let kept = smoothed.contains { hypot($0.x - jog.x, $0.y - jog.y) < 0.2 }
        XCTAssertTrue(kept, "low-protrusion micro-jog must remain (no densify teeth)")
    }

    func testGamajiCurve3ShortArcPreservesApproach() {
        let fixture = UITestMountainPathFixtures.gamajicheon
        let coords: [CLLocationCoordinate2D] = fixture.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        let apexIdx = 232
        let apex = coords[apexIdx]
        XCTAssertEqual(apex.latitude, 37.64200773, accuracy: 1e-7)
        let apexLoc = CLLocation(latitude: apex.latitude, longitude: apex.longitude)

        let smoothed = RouteCornerSmoothing.smoothCoordinates(coords)
        let minCut = smoothed.map {
            apexLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? 0
        XCTAssertGreaterThan(minCut, 0.15, "tip should round slightly")
        XCTAssertLessThan(minCut, 1.6, "tip cut must stay short for tipzoom; got \(minCut)")

        // Neighbor seeds (228, 231) must remain as raw verts — only tip replaced.
        for idx in [228, 231] {
            let c = coords[idx]
            let loc = CLLocation(latitude: c.latitude, longitude: c.longitude)
            let nearest = smoothed.map {
                loc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
            }.min() ?? 999
            XCTAssertLessThan(nearest, 0.2, "neighbor seed \(idx) must stay (not filleted); d=\(nearest)")
        }

        // Outside 4m of tip, every smoothed point hugs a raw vertex (no approach rewrite).
        var maxApproachDev: CLLocationDistance = 0
        for s in smoothed {
            let sLoc = CLLocation(latitude: s.latitude, longitude: s.longitude)
            let dApex = sLoc.distance(from: apexLoc)
            if dApex < 4 || dApex > 35 { continue }
            let d = coords.map {
                sLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
            }.min() ?? 999
            maxApproachDev = max(maxApproachDev, d)
        }
        XCTAssertLessThan(maxApproachDev, 0.25, "approach rewrite; maxDev=\(maxApproachDev)")
        print("CURVE3_V2G minCut=\(minCut) maxApproachDev=\(maxApproachDev)")
    }

    func testGamajiFilletThenStretchLocal() {
        let fixture = UITestMountainPathFixtures.gamajicheon
        let coords: [CLLocationCoordinate2D] = fixture.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        let apex = coords[232]
        let apexLoc = CLLocation(latitude: apex.latitude, longitude: apex.longitude)
        let filleted = RouteCornerSmoothing.smoothCoordinates(coords)
        let stretches = RouteSelfCrossing.chronologicalCoordinateStretches(in: filleted)
        let all = (stretches.isEmpty ? [filleted] : stretches).flatMap { $0 }
        let minCut = all.map {
            apexLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? 0
        XCTAssertGreaterThan(minCut, 0.15)
        XCTAssertLessThan(minCut, 1.6)
    }
}
