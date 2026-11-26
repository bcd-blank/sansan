import XCTest
@testable import sansan
import CoreGraphics
import CoreLocation

final class RouteCornerSmoothingTests: XCTestCase {
    func testSharpCornerGetsFilletSamples() {
        // Right-angle (90°) corner — above 30° threshold.
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 40, y: 0),
            CGPoint(x: 40, y: 40)
        ]
        let smoothed = RouteCornerSmoothing.smoothPoints(
            points,
            radius: 12,
            maxAlong: 28,
            minTurnDegrees: 30,
            samples: 10
        )
        XCTAssertGreaterThan(smoothed.count, points.count, "fillet must insert samples")
        XCTAssertEqual(smoothed.first, points.first)
        XCTAssertEqual(smoothed.last, points.last)
        let hasExactApex = smoothed.contains { hypot($0.x - 40, $0.y - 0) < 0.05 }
        XCTAssertFalse(hasExactApex, "exact sharp apex should be replaced by fillet")
    }

    /// curve3-class ~42° adjacent elbow must fillet under v2 30° threshold.
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
        XCTAssertGreaterThan(minDist, 2.0, "circular fillet must visibly leave the apex")
    }

    /// Compound tip like Gamaji curve3: short zigzags that window to ~90°.
    /// Extended arms must cut the tip far enough for eye-diff at 4× zoom.
    func testCompoundTipExtendedArmCutsApex() {
        // Build a pointed zigzag: inbound east, three short jogs, outbound NE.
        var points: [CGPoint] = [CGPoint(x: 0, y: 0)]
        points.append(CGPoint(x: 40, y: 0))
        points.append(CGPoint(x: 46, y: 2))
        points.append(CGPoint(x: 50, y: 0)) // visual tip
        points.append(CGPoint(x: 54, y: 6))
        points.append(CGPoint(x: 70, y: 28))
        let tip = points[3]
        let smoothed = RouteCornerSmoothing.smoothPoints(
            points,
            radius: 12,
            maxAlong: 28,
            minTurnDegrees: 30,
            samples: 10
        )
        XCTAssertGreaterThan(smoothed.count, 2)
        let minDist = smoothed.map { hypot($0.x - tip.x, $0.y - tip.y) }.min() ?? 0
        XCTAssertGreaterThan(minDist, 3.5, "extended-arm fillet must clear compound tip for eye-diff")
        let hasExactTip = smoothed.contains { hypot($0.x - tip.x, $0.y - tip.y) < 0.2 }
        XCTAssertFalse(hasExactTip, "compound tip vertex must not remain")
    }

    func testGentleTurnUnchanged() {
        // ~15° bend — below 30° threshold.
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 50, y: 0),
            CGPoint(x: 100, y: 13)
        ]
        let smoothed = RouteCornerSmoothing.smoothPoints(
            points,
            radius: 12,
            maxAlong: 28,
            minTurnDegrees: 30,
            samples: 10
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

    /// Gamaji curve3 camera vertex must move ≥2.5m under map-space cluster fillet.
    func testGamajiCurve3ApexCutMeters() {
        let fixture = UITestMountainPathFixtures.gamajicheon
        let coords: [CLLocationCoordinate2D] = fixture.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        XCTAssertGreaterThanOrEqual(coords.count, 240)
        let apexIdx = 232
        let apex = coords[apexIdx]
        // Camera SoT for curve3.
        XCTAssertEqual(apex.latitude, 37.64200773, accuracy: 1e-7)
        XCTAssertEqual(apex.longitude, 126.63898472, accuracy: 1e-7)

        let smoothed = RouteCornerSmoothing.smoothCoordinates(coords)
        XCTAssertGreaterThan(smoothed.count, 2)

        let apexLoc = CLLocation(latitude: apex.latitude, longitude: apex.longitude)
        let minMeters = smoothed.map {
            apexLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? 0
        XCTAssertGreaterThan(
            minMeters,
            2.5,
            "curve3 apex must be cut by ≥2.5m for 4× eye-diff; got \(minMeters)m"
        )
    }

    func testGamajiCurve3ReportsCutDistance() {
        let fixture = UITestMountainPathFixtures.gamajicheon
        let coords: [CLLocationCoordinate2D] = fixture.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        let apex = coords[232]
        let apexLoc = CLLocation(latitude: apex.latitude, longitude: apex.longitude)
        let smoothed = RouteCornerSmoothing.smoothCoordinates(coords)
        let minMeters = smoothed.map {
            apexLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? 0
        // Log for capture tuning.
        print("CURVE3_APEX_CUT_M=\(minMeters) smoothedCount=\(smoothed.count) rawCount=\(coords.count)")
        XCTAssertGreaterThan(minMeters, 2.5)
    }

    /// Live map order: fillet full path, then stretch-split.
    func testGamajiCurve3ApexCutAfterStretchSplit() {
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
        let minMeters = all.map {
            apexLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? 0
        XCTAssertGreaterThan(
            minMeters,
            2.5,
            "after fillet-then-stretch, curve3 apex must still be cut ≥2.5m; got \(minMeters)m; stretches=\(list.count)"
        )
    }

    /// Local cluster only: curve3 must keep densified arc samples near the apex
    /// (no 30m chord from a merged distant elbow).
    func testGamajiCurve3HasLocalArcNotDistantChord() {
        let fixture = UITestMountainPathFixtures.gamajicheon
        let coords: [CLLocationCoordinate2D] = fixture.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        let apex = coords[232]
        let apexLoc = CLLocation(latitude: apex.latitude, longitude: apex.longitude)
        let smoothed = RouteCornerSmoothing.smoothCoordinates(coords)
        let near = smoothed.filter {
            apexLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= 20
        }
        let minCut = smoothed.map {
            apexLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? -1
        // Consecutive near-apex samples in path order should not jump >12m.
        var maxGap: CLLocationDistance = 0
        for i in 0..<(smoothed.count - 1) {
            let a = smoothed[i], b = smoothed[i + 1]
            let da = apexLoc.distance(from: CLLocation(latitude: a.latitude, longitude: a.longitude))
            let db = apexLoc.distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            guard da <= 25 || db <= 25 else { continue }
            let gap = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            maxGap = max(maxGap, gap)
        }
        print("CURVE3_LOCAL near=\(near.count) minCut=\(minCut) maxGap=\(maxGap) smoothed=\(smoothed.count)")
        XCTAssertGreaterThanOrEqual(near.count, 6, "local fillet arc must densify near curve3; got \(near.count) minCut=\(minCut) maxGap=\(maxGap)")
        XCTAssertLessThan(maxGap, 12, "curve3 must not be a distant-elbow chord; maxGap=\(maxGap)m near=\(near.count) minCut=\(minCut)")
    }
}
