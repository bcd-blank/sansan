import XCTest
@testable import sansan
import CoreGraphics
import CoreLocation
import MapKit

final class RouteCornerSmoothingTests: XCTestCase {
    func testAlongPtIsOnePercentOfMinSide() {
        XCTAssertEqual(RouteCornerSmoothing.alongPt(mapWidth: 390, mapHeight: 420), 3.9, accuracy: 1e-9)
        XCTAssertEqual(RouteCornerSmoothing.alongPt(mapWidth: 400, mapHeight: 200), 2.0, accuracy: 1e-9)
    }

    func testSharpCornerGetsBezierSamples() {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 40, y: 0),
            CGPoint(x: 40, y: 40)
        ]
        let smoothed = RouteCornerSmoothing.smoothPoints(points, maxAlong: 8)
        XCTAssertGreaterThan(smoothed.count, points.count)
        XCTAssertEqual(smoothed.first, points.first)
        XCTAssertEqual(smoothed.last, points.last)
        XCTAssertFalse(smoothed.contains { hypot($0.x - 40, $0.y - 0) < 0.05 })
    }

    func testEveryInteriorBendGetsFilletIncludingShallow() {
        // ~15° bend must still fillet (30° gate removed).
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 50, y: 0),
            CGPoint(x: 100, y: 13)
        ]
        let tip = points[1]
        let smoothed = RouteCornerSmoothing.smoothPoints(points, maxAlong: 10)
        XCTAssertFalse(smoothed.contains { hypot($0.x - tip.x, $0.y - tip.y) < 0.2 })
        XCTAssertGreaterThan(smoothed.count, points.count)
    }

    func testColinearUnchanged() {
        let points: [CGPoint] = (0..<8).map { CGPoint(x: CGFloat($0) * 10, y: 0) }
        XCTAssertEqual(RouteCornerSmoothing.smoothPoints(points, maxAlong: 4).count, points.count)
    }

    /// Tipzoom ~(237,62) upper ~50° bend (idx 231) must fillet under fit L.
    func testUpperBendNearCurve3IsFilleted() {
        let fixture = UITestMountainPathFixtures.gamajicheon
        let coords: [CLLocationCoordinate2D] = fixture.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        XCTAssertGreaterThanOrEqual(coords.count, 233)
        let apex = coords[231]
        let region = HikingMapRegion.fitting(
            coordinates: coords,
            viewSize: CGSize(width: 390, height: 420)
        )
        let smoothed = RouteCornerSmoothing.smoothCoordinates(
            coords,
            fittingRegion: region,
            mapWidth: 390,
            mapHeight: 420
        )
        let apexLoc = CLLocation(latitude: apex.latitude, longitude: apex.longitude)
        let minCut = smoothed.map {
            apexLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? 0
        XCTAssertGreaterThan(minCut, 0.02, "idx 231 must be cut")
    }

    func testGamajiCurve3TipCutAtFitL() {
        let fixture = UITestMountainPathFixtures.gamajicheon
        let coords: [CLLocationCoordinate2D] = fixture.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        let apex = coords[232]
        XCTAssertEqual(apex.latitude, 37.64200773, accuracy: 1e-7)
        let region = HikingMapRegion.fitting(
            coordinates: coords,
            viewSize: CGSize(width: 390, height: 420)
        )
        let mpp = RouteCornerSmoothing.metersPerPoint(
            latitude: region.center.latitude,
            visibleMapRect: region.mapRect,
            boundsWidth: 390
        )
        let L = RouteCornerSmoothing.alongPt(mapWidth: 390, mapHeight: 420)
        XCTAssertEqual(L, 3.9, accuracy: 1e-9)
        let tM = RouteCornerSmoothing.maxAlongMeters(metersPerPoint: mpp, alongPt: L)
        XCTAssertGreaterThan(tM, 0)
        let smoothed = RouteCornerSmoothing.smoothCoordinates(
            coords,
            metersPerPoint: mpp,
            alongPt: L
        )
        let apexLoc = CLLocation(latitude: apex.latitude, longitude: apex.longitude)
        let minCut = smoothed.map {
            apexLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? 0
        XCTAssertGreaterThan(minCut, 0.02)
        XCTAssertEqual(smoothed.first!.latitude, coords.first!.latitude, accuracy: 1e-9)
        XCTAssertEqual(smoothed.last!.latitude, coords.last!.latitude, accuracy: 1e-9)
        XCTAssertGreaterThan(smoothed.count, coords.count)
    }

    func testGamajiFilletThenStretchLocal() {
        let fixture = UITestMountainPathFixtures.gamajicheon
        let coords: [CLLocationCoordinate2D] = fixture.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        let apex = coords[232]
        let apexLoc = CLLocation(latitude: apex.latitude, longitude: apex.longitude)
        let region = HikingMapRegion.fitting(
            coordinates: coords,
            viewSize: CGSize(width: 390, height: 420)
        )
        let filleted = RouteCornerSmoothing.smoothCoordinates(
            coords,
            fittingRegion: region,
            mapWidth: 390,
            mapHeight: 420
        )
        let stretches = RouteSelfCrossing.chronologicalCoordinateStretches(in: filleted)
        let all = (stretches.isEmpty ? [filleted] : stretches).flatMap { $0 }
        let minCut = all.map {
            apexLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? 0
        XCTAssertGreaterThan(minCut, 0.02)
    }
}
