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
        // Tight accuracy → dejitter never fires; validates Catmull through-points gates.
        var stats = RouteCornerSmoothing.DejitterStats()
        let smoothed = RouteCornerSmoothing.smoothCoordinates(
            coords,
            accuraciesMeters: Array(repeating: 0.1, count: coords.count),
            metersPerPoint: mpp,
            alongPt: L,
            statsOut: &stats
        )
        XCTAssertEqual(stats.removedCount, 0)
        XCTAssertEqual(smoothed.first!.latitude, coords.first!.latitude, accuracy: 1e-9)
        XCTAssertEqual(smoothed.last!.latitude, coords.last!.latitude, accuracy: 1e-9)
        XCTAssertGreaterThan(smoothed.count, coords.count)

        // Pass: every raw point ≤0.5m from render line (no removals).
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

    func testDejitterRemovesReboundSpike() {
        // Straight run with a sharp rebound (heading ~180°, short arms, poor acc).
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 20, y: 0),
            CGPoint(x: 25, y: 0),
            CGPoint(x: 22, y: 8), // spike
            CGPoint(x: 30, y: 0),
            CGPoint(x: 50, y: 0)
        ]
        let acc: [CGFloat] = [5, 5, 5, 15, 5, 5]
        var stats = RouteCornerSmoothing.DejitterStats()
        let smoothed = RouteCornerSmoothing.smoothPoints(
            points,
            metersPerUnit: 1,
            metersPerScreenPoint: 1,
            accuraciesMeters: acc,
            statsOut: &stats
        )
        XCTAssertGreaterThanOrEqual(stats.removedCount, 1)
        XCTAssertEqual(smoothed.first!.x, 0, accuracy: 1e-6)
        XCTAssertEqual(smoothed.last!.x, 50, accuracy: 1e-6)
        // Spike must not sit on the final polyline (far from y=0 line).
        let spikeNear = smoothed.contains { hypot($0.x - 22, $0.y - 8) < 1.0 }
        XCTAssertFalse(spikeNear, "dejitter must drop rebound spike")
    }

    func testPauseSegmentsDoNotBridgeGap() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let points: [HikingPoint] = [
            HikingPoint(id: UUID(), latitude: 37.0, longitude: 127.0, altitude: 0, timestamp: t0, horizontalAccuracy: 5),
            HikingPoint(id: UUID(), latitude: 37.001, longitude: 127.0, altitude: 0, timestamp: t0.addingTimeInterval(10), horizontalAccuracy: 5),
            HikingPoint(id: UUID(), latitude: 37.002, longitude: 127.0, altitude: 0, timestamp: t0.addingTimeInterval(20), horizontalAccuracy: 5),
            // pause at +30s, resume at +90s — mid-pause GPS excluded
            HikingPoint(id: UUID(), latitude: 37.010, longitude: 127.0, altitude: 0, timestamp: t0.addingTimeInterval(50), horizontalAccuracy: 5),
            HikingPoint(id: UUID(), latitude: 37.020, longitude: 127.0, altitude: 0, timestamp: t0.addingTimeInterval(100), horizontalAccuracy: 5),
            HikingPoint(id: UUID(), latitude: 37.021, longitude: 127.0, altitude: 0, timestamp: t0.addingTimeInterval(110), horizontalAccuracy: 5),
            HikingPoint(id: UUID(), latitude: 37.022, longitude: 127.0, altitude: 0, timestamp: t0.addingTimeInterval(120), horizontalAccuracy: 5)
        ]
        let breaks = [
            HikingSegmentBreak(
                id: UUID(),
                pauseLatitude: 37.002,
                pauseLongitude: 127.0,
                pauseTime: t0.addingTimeInterval(30),
                resumeLatitude: 37.020,
                resumeLongitude: 127.0,
                resumeTime: t0.addingTimeInterval(90)
            )
        ]
        let segs = RouteCornerSmoothing.pausePointSegments(from: points, segmentBreaks: breaks)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].count, 3)
        XCTAssertEqual(segs[1].count, 3)

        let region = HikingMapRegion.fitting(
            coordinates: points.map(\.coordinate),
            viewSize: CGSize(width: 390, height: 420)
        )
        let rendered = RouteCornerSmoothing.smoothRenderSegments(
            points: points,
            segmentBreaks: breaks,
            fittingRegion: region,
            mapWidth: 390,
            mapHeight: 420
        )
        XCTAssertEqual(rendered.count, 2)
        // No polyline may contain both pre-pause last and post-resume first.
        let preLast = segs[0].last!.coordinate
        let postFirst = segs[1].first!.coordinate
        for poly in rendered {
            let hasPre = poly.contains {
                abs($0.latitude - preLast.latitude) < 1e-9
                    && abs($0.longitude - preLast.longitude) < 1e-9
            }
            let hasPost = poly.contains {
                abs($0.latitude - postFirst.latitude) < 1e-9
                    && abs($0.longitude - postFirst.longitude) < 1e-9
            }
            XCTAssertFalse(hasPre && hasPost, "pause gap must not be bridged")
        }
    }

    func testSinglePointPauseSegmentYieldsNoLine() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let points: [HikingPoint] = [
            HikingPoint(id: UUID(), latitude: 37.0, longitude: 127.0, altitude: 0, timestamp: t0, horizontalAccuracy: 5),
            HikingPoint(id: UUID(), latitude: 37.001, longitude: 127.0, altitude: 0, timestamp: t0.addingTimeInterval(10), horizontalAccuracy: 5),
            HikingPoint(id: UUID(), latitude: 37.050, longitude: 127.0, altitude: 0, timestamp: t0.addingTimeInterval(100), horizontalAccuracy: 5)
        ]
        let breaks = [
            HikingSegmentBreak(
                id: UUID(),
                pauseLatitude: 37.001,
                pauseLongitude: 127.0,
                pauseTime: t0.addingTimeInterval(20),
                resumeLatitude: 37.050,
                resumeLongitude: 127.0,
                resumeTime: t0.addingTimeInterval(90)
            )
        ]
        let rendered = RouteCornerSmoothing.smoothRenderSegments(
            points: points,
            segmentBreaks: breaks,
            metersPerPoint: 1,
            alongPt: 4
        )
        // First seg 2 pts → line; second seg 1 pt → no line.
        XCTAssertEqual(rendered.count, 1)
        XCTAssertEqual(rendered[0].first!.latitude, 37.0, accuracy: 1e-9)
    }
}
