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

    func testMidSharpFortyDegreeFillet() {
        let rad = CGFloat.pi * 40 / 180
        let apex = CGPoint(x: 50, y: 0)
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            apex,
            CGPoint(x: 50 + 50 * cos(rad), y: 50 * sin(rad))
        ]
        let smoothed = RouteCornerSmoothing.smoothPoints(points)
        XCTAssertGreaterThan(smoothed.count, points.count)
        let minDist = smoothed.dropFirst().dropLast().map { hypot($0.x - apex.x, $0.y - apex.y) }.min() ?? 0
        XCTAssertGreaterThan(minDist, 0.5)
    }

    /// Weaker neighbor elbows stay as raw verts; only local-max tip is rounded.
    func testWeakerNeighborElbowsPreserved() {
        // Strong tip at (50,0); weaker jog before it should remain.
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 30, y: 0),
            CGPoint(x: 35, y: 3),   // ~weak elbow
            CGPoint(x: 40, y: 0),
            CGPoint(x: 50, y: 0),   // strong tip (~90° into north)
            CGPoint(x: 50, y: 40)
        ]
        let weak = points[2]
        let tip = points[4]
        let smoothed = RouteCornerSmoothing.smoothPoints(points)
        let weakKept = smoothed.contains { hypot($0.x - weak.x, $0.y - weak.y) < 0.2 }
        XCTAssertTrue(weakKept, "weaker neighbor vertex must stay (no teeth densify)")
        let tipKept = smoothed.contains { hypot($0.x - tip.x, $0.y - tip.y) < 0.2 }
        XCTAssertFalse(tipKept, "local-max tip must be replaced by short arc")
        XCTAssertEqual(smoothed.first, points.first)
        XCTAssertEqual(smoothed.last, points.last)
    }

    func testGentleTurnUnchanged() {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 50, y: 0),
            CGPoint(x: 100, y: 13)
        ]
        let smoothed = RouteCornerSmoothing.smoothPoints(points)
        XCTAssertEqual(smoothed.count, points.count)
    }

    func testStraightUnchanged() {
        let points: [CGPoint] = (0..<8).map { CGPoint(x: CGFloat($0) * 10, y: 0) }
        XCTAssertEqual(RouteCornerSmoothing.smoothPoints(points).count, points.count)
    }

    /// Same input: sub-threshold verts identical; path outside fillets matches; tip only slightly cut.
    func testGamajiSameInputPreservesTopologyOutsideTip() {
        let fixture = UITestMountainPathFixtures.gamajicheon
        let coords: [CLLocationCoordinate2D] = fixture.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        let apexIdx = 232
        let apex = coords[apexIdx]
        XCTAssertEqual(apex.latitude, 37.64200773, accuracy: 1e-7)

        let smoothed = RouteCornerSmoothing.smoothCoordinates(coords)
        // Count how many raw verts are missing (>0.5m) — should be few local-max tips only.
        var missing = 0
        var preserved = 0
        for i in 1..<(coords.count - 1) {
            let b = coords[i]
            let bLoc = CLLocation(latitude: b.latitude, longitude: b.longitude)
            let nearest = smoothed.map {
                bLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
            }.min() ?? 999
            if nearest < 0.15 {
                preserved += 1
            } else if nearest > 0.5 {
                missing += 1
            }
        }
        // Vast majority of verts preserved; only local-max tips replaced.
        XCTAssertGreaterThan(preserved, coords.count - 40)
        XCTAssertLessThan(missing, 80, "too many verts replaced — would invent tipzoom teeth; missing=\(missing)")

        let apexLoc = CLLocation(latitude: apex.latitude, longitude: apex.longitude)
        let minCut = smoothed.map {
            apexLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? 0
        XCTAssertGreaterThan(minCut, 0.2, "tip should round slightly")
        XCTAssertLessThan(minCut, 3.0, "tip cut must stay short-arc; got \(minCut)")

        // Hausdorff-ish: every smoothed point near apex stays close to raw path.
        let rawNear = coords.enumerated().compactMap { (i, c) -> CLLocationCoordinate2D? in
            let d = apexLoc.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            return d <= 30 ? c : nil
        }
        var maxDev: CLLocationDistance = 0
        for s in smoothed {
            let sLoc = CLLocation(latitude: s.latitude, longitude: s.longitude)
            if sLoc.distance(from: apexLoc) > 30 { continue }
            let d = rawNear.map {
                sLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
            }.min() ?? 999
            maxDev = max(maxDev, d)
        }
        XCTAssertLessThan(maxDev, 2.6, "smoothed path must hug raw topology; maxDev=\(maxDev)m")
        print("CURVE3_V2F preserved=\(preserved) missing=\(missing) minCut=\(minCut) maxDev=\(maxDev)")
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
        XCTAssertGreaterThan(minCut, 0.2)
        XCTAssertLessThan(minCut, 3.0)
    }
}
