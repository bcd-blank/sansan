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

    func testThroughPointsKeepsApexAndDensifies() {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 40, y: 0),
            CGPoint(x: 40, y: 40)
        ]
        // metersPerUnit=1, mpp=1 → plane units = meters = screen px
        let smoothed = RouteCornerSmoothing.smoothPoints(
            points,
            metersPerUnit: 1,
            metersPerScreenPoint: 1
        )
        XCTAssertGreaterThan(smoothed.count, points.count)
        XCTAssertEqual(smoothed.first!.x, 0, accuracy: 1e-6)
        XCTAssertEqual(smoothed.first!.y, 0, accuracy: 1e-6)
        XCTAssertEqual(smoothed.last!.x, 40, accuracy: 1e-6)
        XCTAssertEqual(smoothed.last!.y, 40, accuracy: 1e-6)
        // v4 through-points: apex must remain on the render line.
        let apexNear = smoothed.contains { hypot($0.x - 40, $0.y - 0) < 1e-5 }
        XCTAssertTrue(apexNear)
        // Curve bows off the incoming chord before the apex (not a flat polyline).
        var maxChordDev: CGFloat = 0
        for i in 0..<(smoothed.count - 1) {
            // chord of first leg (0,0)-(40,0)
            let p = smoothed[i]
            if p.x >= 0, p.x <= 40, abs(p.y) < 20 {
                maxChordDev = max(maxChordDev, abs(p.y))
            }
        }
        XCTAssertGreaterThan(maxChordDev, 0.01, "Catmull must curve, not stay flat on chords")
    }

    func testDropsOnlySubHalfMeterDuplicates() {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0.2, y: 0), // <0.5m → drop
            CGPoint(x: 10, y: 0),
            CGPoint(x: 20, y: 0)
        ]
        let smoothed = RouteCornerSmoothing.smoothPoints(
            points,
            metersPerUnit: 1,
            metersPerScreenPoint: 1
        )
        // Dropped dup must still be ≤0.5m from render line (near start).
        let dup = points[1]
        let d = smoothed.map { hypot($0.x - dup.x, $0.y - dup.y) }.min() ?? 999
        XCTAssertLessThanOrEqual(d, 0.5 + 1e-6)
        XCTAssertGreaterThan(smoothed.count, 2)
    }

    func testColinearStaysOnLine() {
        let points: [CGPoint] = (0..<8).map { CGPoint(x: CGFloat($0) * 10, y: 0) }
        let smoothed = RouteCornerSmoothing.smoothPoints(
            points,
            metersPerUnit: 1,
            metersPerScreenPoint: 1
        )
        XCTAssertEqual(smoothed.first, points.first)
        XCTAssertEqual(smoothed.last, points.last)
        for p in smoothed {
            XCTAssertEqual(p.y, 0, accuracy: 1e-5)
        }
    }

    func testGamajiThroughPointsPassGates() {
        let fixture = UITestMountainPathFixtures.gamajicheon
        let coords: [CLLocationCoordinate2D] = fixture.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
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
        let tM = RouteCornerSmoothing.maxAlongMeters(metersPerPoint: mpp, alongPt: L)
        XCTAssertGreaterThan(tM, 5)
        let smoothed = RouteCornerSmoothing.smoothCoordinates(
            coords,
            metersPerPoint: mpp,
            alongPt: L
        )
        XCTAssertEqual(smoothed.first!.latitude, coords.first!.latitude, accuracy: 1e-9)
        XCTAssertEqual(smoothed.last!.latitude, coords.last!.latitude, accuracy: 1e-9)
        XCTAssertGreaterThan(smoothed.count, coords.count)

        // Pass: every raw point ≤0.5m from render line.
        var maxDev = 0.0
        for c in coords {
            let loc = CLLocation(latitude: c.latitude, longitude: c.longitude)
            let d = smoothed.map {
                loc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
            }.min() ?? 0
            maxDev = max(maxDev, d)
        }
        XCTAssertLessThanOrEqual(maxDev, 0.5 + 1e-3, "raw→line maxdev \(maxDev)m")

        // Max chord deviation (Catmull bow vs straight between consecutive kept).
        var maxChord = 0.0
        for i in 0..<(coords.count - 1) {
            let a = coords[i]
            let b = coords[i + 1]
            let aLoc = CLLocation(latitude: a.latitude, longitude: a.longitude)
            let ab = aLoc.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            if ab < 0.5 { continue }
            // Sample mid of smooth verts whose nearest raw segment is i.
            for s in smoothed {
                let dA = CLLocation(latitude: s.latitude, longitude: s.longitude)
                    .distance(from: aLoc)
                let dB = CLLocation(latitude: s.latitude, longitude: s.longitude)
                    .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
                if dA + dB > ab * 1.05 { continue }
                // Distance to chord via cross-track approx in ENU.
                let midLat = (a.latitude + b.latitude) / 2
                let mLat = 111_320.0
                let mLon = 111_320.0 * cos(midLat * .pi / 180)
                let ax = 0.0, ay = 0.0
                let bx = (b.longitude - a.longitude) * mLon
                let by = (b.latitude - a.latitude) * mLat
                let sx = (s.longitude - a.longitude) * mLon
                let sy = (s.latitude - a.latitude) * mLat
                let denom = max(hypot(bx, by), 1e-9)
                let cross = abs(bx * sy - by * sx) / denom
                maxChord = max(maxChord, cross)
            }
        }
        XCTAssertGreaterThan(maxChord, 0.01, "curves not flats; chordDev=\(maxChord)")

        // Heading Δ of interpolated vs raw: smoothed consecutive heading jumps reduced.
        func maxHeadingDelta(_ poly: [CLLocationCoordinate2D]) -> Double {
            guard poly.count >= 3 else { return 0 }
            var maxD = 0.0
            for i in 1..<(poly.count - 1) {
                let a = poly[i - 1], b = poly[i], c = poly[i + 1]
                let h1 = atan2(b.longitude - a.longitude, b.latitude - a.latitude)
                let h2 = atan2(c.longitude - b.longitude, c.latitude - b.latitude)
                var d = abs(h2 - h1) * 180 / .pi
                if d > 180 { d = 360 - d }
                maxD = max(maxD, d)
            }
            return maxD
        }
        let rawH = maxHeadingDelta(coords)
        let smoothH = maxHeadingDelta(smoothed)
        XCTAssertLessThan(smoothH, rawH, "headingΔ smooth \(smoothH) should be < raw \(rawH)")
    }

    func testStretchOnSmoothedKeepsLayers() {
        let fixture = UITestMountainPathFixtures.gamajicheon
        let coords: [CLLocationCoordinate2D] = fixture.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
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
        let stretches = RouteSelfCrossing.chronologicalCoordinateStretches(in: smoothed)
        XCTAssertFalse(stretches.isEmpty || stretches.allSatisfy { $0.count < 2 })
    }

    func testSortByTimestampOptional() {
        struct P { let id: Int; let t: Date? }
        let items = [
            P(id: 0, t: Date(timeIntervalSince1970: 30)),
            P(id: 1, t: Date(timeIntervalSince1970: 10)),
            P(id: 2, t: Date(timeIntervalSince1970: 20))
        ]
        let same = RouteCornerSmoothing.sortByTimestampIfNeeded(
            items, timestamp: \.t, saveOrderMatchesTimestamp: true
        )
        XCTAssertEqual(same.map(\.id), [0, 1, 2])
        let sorted = RouteCornerSmoothing.sortByTimestampIfNeeded(
            items, timestamp: \.t, saveOrderMatchesTimestamp: false
        )
        XCTAssertEqual(sorted.map(\.id), [1, 2, 0])
    }
}
