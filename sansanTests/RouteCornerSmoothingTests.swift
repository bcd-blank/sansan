import XCTest
@testable import sansan
import CoreGraphics
import CoreLocation

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
        XCTAssertFalse(smoothed.contains { hypot($0.x - 40, $0.y - 0) < 0.05 })
    }

    func testEveryGe30GetsArcNotOnlyLocalMax() {
        // Two ≥30° tips far apart — both must fillet (spec: each P(i)).
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 50, y: 0),
            CGPoint(x: 50, y: 50),
            CGPoint(x: 100, y: 50),
            CGPoint(x: 100, y: 100)
        ]
        let tip1 = points[1]
        let tip2 = points[3]
        let smoothed = RouteCornerSmoothing.smoothPoints(points)
        XCTAssertFalse(smoothed.contains { hypot($0.x - tip1.x, $0.y - tip1.y) < 0.2 })
        XCTAssertFalse(smoothed.contains { hypot($0.x - tip2.x, $0.y - tip2.y) < 0.2 })
        XCTAssertEqual(smoothed.first, points.first)
        XCTAssertEqual(smoothed.last, points.last)
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

    func testGamajiCurve3TipCutAndNeighborsOnIncidentOnly() {
        let fixture = UITestMountainPathFixtures.gamajicheon
        let coords: [CLLocationCoordinate2D] = fixture.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        let apex = coords[232]
        XCTAssertEqual(apex.latitude, 37.64200773, accuracy: 1e-7)
        let apexLoc = CLLocation(latitude: apex.latitude, longitude: apex.longitude)
        let smoothed = RouteCornerSmoothing.smoothCoordinates(coords)
        let minCut = smoothed.map {
            apexLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? 0
        XCTAssertGreaterThan(minCut, 0.15)
        XCTAssertLessThan(minCut, 1.6)

        // Non-filleted verts far from any ≥30° tip stay bit-identical in position.
        // Spot-check a gentle mid-leg vertex (idx 224 turn≈0.8°).
        let gentle = coords[224]
        let gLoc = CLLocation(latitude: gentle.latitude, longitude: gentle.longitude)
        let nearest = smoothed.map {
            gLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? 999
        XCTAssertLessThan(nearest, 0.15)
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
