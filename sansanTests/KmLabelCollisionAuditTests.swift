#if os(iOS)
import XCTest
import CoreLocation
@testable import sansan

final class KmLabelCollisionAuditTests: XCTestCase {

    func testPathThroughCapsuleDetectedInScreenSpace() {
        // Polyline crosses the capsule interior — old outline-sample gate missed this.
        let poly = [CGPoint(x: 70, y: 100), CGPoint(x: 130, y: 100)]
        let markers = [
            RouteKilometerLabelRequest(
                kilometer: 1,
                distanceLabel: "1km",
                timeLabel: "10:00",
                routePoint: CGPoint(x: 100, y: 130),
                preferredLeadingSide: false
            )
        ]
        let shift = RouteKilometerLabelShift(centerOffset: CGPoint(x: 0, y: -30))
        let counts = RouteKilometerLabelPlacement.auditCollisions(
            shifts: [1: shift],
            markers: markers,
            endpointPoints: [],
            routePolyline: poly,
            contentScale: 1,
            pathHalfWidth: 4
        )
        XCTAssertGreaterThan(counts.labelPath, 0, "interior path must count as label-path collision")
    }

    func testJWMountainFixturesPlacementCollisionZero() throws {
        continueAfterFailure = false
        let previousBudget = RouteKilometerLabelPlacement.softTimeBudgetSeconds
        RouteKilometerLabelPlacement.softTimeBudgetSeconds = 2.0
        defer { RouteKilometerLabelPlacement.softTimeBudgetSeconds = previousBudget }

        let inset: CGFloat = 24
        var lines: [String] = [
            "screen=pt pathHalf.summary=4 pathHalf.detail=4 clear.strict=route2/point+2/label3"
        ]
        var allZero = true

        for fixture in UITestMountainPathFixtures.all {
            // Project at a scale that keeps ≥96pt/km so capsules can satisfy own-point rules.
            let summaryPoly = project(
                fixture.points.map { ($0.lat, $0.lon) },
                canvas: CGSize(width: 430, height: 760),
                inset: inset,
                minPtPerKm: 96
            )
            let detailPoly = project(
                fixture.points.map { ($0.lat, $0.lon) },
                canvas: CGSize(width: 390, height: 320),
                inset: inset,
                minPtPerKm: 96
            )
            let summaryCanvas = canvasFitting(summaryPoly, pad: 40)
            let detailCanvas = canvasFitting(detailPoly, pad: 36)
            XCTAssertGreaterThan(summaryPoly.count, 10, fixture.title)
            let summaryMarkers = geographicMarkers(fixture: fixture, screenPoly: summaryPoly)
            let detailMarkers = geographicMarkers(fixture: fixture, screenPoly: detailPoly)
            XCTAssertFalse(summaryMarkers.isEmpty, "\(fixture.title) must have km markers")
            let summaryEnds = [summaryPoly.first!, summaryPoly.last!]
            let detailEnds = [detailPoly.first!, detailPoly.last!]

            let summary = RouteKilometerLabelPlacement.placeSummary(
                markers: summaryMarkers,
                endpointPoints: summaryEnds,
                routePolyline: summaryPoly,
                contentScale: 1,
                imageSize: summaryCanvas,
                sideInset: 24,
                pathHalfWidth: ShareSummaryTokens.routeCasing / 2
            )
            let detail = RouteKilometerLabelPlacement.placeDetail(
                markers: detailMarkers,
                endpointPoints: detailEnds,
                routePolyline: detailPoly,
                contentScale: 1,
                imageSize: detailCanvas,
                preferModeStep: 1,
                zoomDelta: 1,
                pathHalfWidth: 4
            )
            // Stages C/D may use relaxed clear (§2); audit with the clearance the solver allowed.
            let summaryClear = clearanceForStage(summary.stageName)
            let detailClear = clearanceForStage(detail.stageName)
            let summaryHits = RouteKilometerLabelPlacement.auditCollisions(
                shifts: summary.shifts,
                markers: summaryMarkers,
                endpointPoints: summaryEnds,
                routePolyline: summaryPoly,
                contentScale: 1,
                pathHalfWidth: ShareSummaryTokens.routeCasing / 2,
                clear: summaryClear
            )
            let detailHits = RouteKilometerLabelPlacement.auditCollisions(
                shifts: detail.shifts,
                markers: detailMarkers,
                endpointPoints: detailEnds,
                routePolyline: detailPoly,
                contentScale: 1,
                pathHalfWidth: 4,
                clear: detailClear
            )
            let key: String = {
                switch fixture.title {
                case "사량도": return "saryangdo"
                case "가현산": return "gahyeonsan"
                case "가마지천 산책": return "gamajicheon"
                default: return "samaksan"
                }
            }()
            lines.append(
                "ios-summary-\(key) title=\(fixture.title) dist=\(Int(fixture.totalDistance))m stage=\(summary.stageName) labels=\(summary.shifts.count)/\(summaryMarkers.count) \(summaryHits.line)"
            )
            lines.append(
                "ios-detail-\(key) title=\(fixture.title) dist=\(Int(fixture.totalDistance))m stage=\(detail.stageName) labels=\(detail.shifts.count)/\(detailMarkers.count) \(detailHits.line)"
            )
            // Collision gate (JW): every capture must report 겹침 0.
            XCTAssertFalse(summary.shifts.isEmpty, "summary \(key) placed no labels")
            XCTAssertFalse(detail.shifts.isEmpty, "detail \(key) placed no labels")
            XCTAssertTrue(summaryHits.isZero, lines[lines.count - 2])
            XCTAssertTrue(detailHits.isZero, lines.last!)
            // Prefer full 1km when the solver stayed in mode 1.
            if summary.modeStep == 1 {
                XCTAssertEqual(
                    summary.shifts.count,
                    summaryMarkers.count,
                    "summary \(key) mode1 must place all labels"
                )
            }
            if detail.modeStep == 1 {
                XCTAssertEqual(
                    detail.shifts.count,
                    detailMarkers.count,
                    "detail \(key) mode1 must place all labels"
                )
            }
            if !summaryHits.isZero || !detailHits.isZero { allZero = false }
        }

        lines.append(allZero ? "RESULT=겹침0" : "RESULT=FAIL")
        let text = lines.joined(separator: "\n") + "\n"
        let outs = [
            URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("km-label-COLLISION.txt"),
            URL(
                fileURLWithPath: "/Users/jeongwook/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-75707dba-5737-4d43-b5ab-a5deda5241a4/files/docs/label-placement/final/impl-ios/COLLISION.txt"
            )
        ]
        for url in outs {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
        NSLog("%@", "[km-label-collision]\n\(text)")
        XCTAssertTrue(allZero, text)
    }

    private func canvasFitting(_ poly: [CGPoint], pad: CGFloat) -> CGSize {
        guard let minX = poly.map(\.x).min(),
              let maxX = poly.map(\.x).max(),
              let minY = poly.map(\.y).min(),
              let maxY = poly.map(\.y).max() else {
            return CGSize(width: 430, height: 760)
        }
        return CGSize(
            width: max(430, maxX - minX + pad * 2),
            height: max(320, maxY - minY + pad * 2)
        )
    }

    private func clearanceForStage(_ stageName: String) -> RouteKilometerLabelPlacement.Clearance {
        // "C", "D", "5/C", "5/D", or partial markers that include C/D.
        let upper = stageName.uppercased()
        if upper.contains("C") || upper.contains("D") {
            return .relaxed
        }
        return .strict
    }

    private func project(
        _ coords: [(Double, Double)],
        canvas: CGSize,
        inset: CGFloat,
        minPtPerKm: CGFloat = 0
    ) -> [CGPoint] {
        guard let minLat = coords.map(\.0).min(),
              let maxLat = coords.map(\.0).max(),
              let minLon = coords.map(\.1).min(),
              let maxLon = coords.map(\.1).max() else { return [] }
        let dLat = max(maxLat - minLat, 1e-6)
        let dLon = max(maxLon - minLon, 1e-6)
        // Match MKMap fit padding so km spacing mirrors device captures.
        let availW = (canvas.width - inset * 2) * 0.72
        let availH = (canvas.height - inset * 2) * 0.72
        let scale = min(availW / CGFloat(dLon), availH / CGFloat(dLat))
        var pts = coords.map { lat, lon in
            CGPoint(
                x: CGFloat(lon - minLon) * scale,
                y: CGFloat(maxLat - lat) * scale
            )
        }
        if minPtPerKm > 0, pts.count >= 2 {
            var pathLen: CGFloat = 0
            for i in 1..<pts.count {
                pathLen += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
            }
            let kmEst = max(1, Int(floor(pathLen / 40))) // temporary; refined after geo markers
            // Target: screen path length ≥ kmCount * minPtPerKm. Use geo path km from span.
            var pathM: Double = 0
            for i in 1..<coords.count {
                let a = coords[i - 1]
                let b = coords[i]
                let midLat = (a.0 + b.0) / 2
                let mLon = 111_320.0 * cos(midLat * .pi / 180)
                let dx = (b.1 - a.1) * mLon
                let dy = (b.0 - a.0) * 110_540.0
                pathM += (dx * dx + dy * dy).squareRoot()
            }
            let kmCount = max(1.0, floor(pathM / 1000.0))
            let need = CGFloat(kmCount) * minPtPerKm
            if pathLen > 1, pathLen < need {
                let factor = need / pathLen
                let cx = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
                let cy = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
                pts = pts.map {
                    CGPoint(x: cx + ($0.x - cx) * factor, y: cy + ($0.y - cy) * factor)
                }
            }
            _ = kmEst
        }
        let minX = pts.map(\.x).min() ?? 0
        let minY = pts.map(\.y).min() ?? 0
        let pad: CGFloat = 48
        pts = pts.map { CGPoint(x: $0.x - minX + pad, y: $0.y - minY + pad) }
        return pts
    }

    private func geographicMarkers(
        fixture: UITestMountainPathFixtures.Fixture,
        screenPoly: [CGPoint]
    ) -> [RouteKilometerLabelRequest] {
        let pts = fixture.points
        guard pts.count >= 2, screenPoly.count >= 2 else { return [] }
        var geoCum: [Double] = [0]
        for i in 1..<pts.count {
            let a = CLLocation(latitude: pts[i - 1].lat, longitude: pts[i - 1].lon)
            let b = CLLocation(latitude: pts[i].lat, longitude: pts[i].lon)
            geoCum.append(geoCum[i - 1] + b.distance(from: a))
        }
        let measured = geoCum.last ?? 0
        // Use measured polyline length for km ticks (matches projected screen geometry).
        let kmMax = Int(floor(min(measured, fixture.totalDistance) / 1000.0))
        guard kmMax >= 1, measured > 1 else { return [] }

        // screenPoly is a uniform downsample of pts — map geo index → screen index.
        let ratio = CGFloat(screenPoly.count - 1) / CGFloat(pts.count - 1)

        var markers: [RouteKilometerLabelRequest] = []
        for km in 1...kmMax {
            let target = Double(km) * 1000.0
            var idx = 1
            while idx < geoCum.count, geoCum[idx] < target { idx += 1 }
            if idx >= geoCum.count { idx = geoCum.count - 1 }
            let i1 = max(1, idx)
            let i0 = i1 - 1
            let seg = max(geoCum[i1] - geoCum[i0], 1e-6)
            let t = min(1, max(0, (target - geoCum[i0]) / seg))

            let s0 = min(screenPoly.count - 1, Int((CGFloat(i0) * ratio).rounded()))
            let s1 = min(screenPoly.count - 1, Int((CGFloat(i1) * ratio).rounded()))
            let p = CGPoint(
                x: screenPoly[s0].x + (screenPoly[s1].x - screenPoly[s0].x) * CGFloat(t),
                y: screenPoly[s0].y + (screenPoly[s1].y - screenPoly[s0].y) * CGFloat(t)
            )
            let elapsed = pts[i0].offset + (pts[i1].offset - pts[i0].offset) * t
            let h = Int(elapsed) / 3600
            let m = (Int(elapsed) % 3600) / 60
            let s = Int(elapsed) % 60
            let time: String = h > 0
                ? String(format: "%d:%02d:%02d", h, m, s)
                : String(format: "%d:%02d", m, s)
            markers.append(
                RouteKilometerLabelRequest(
                    kilometer: km,
                    distanceLabel: "\(km)km",
                    timeLabel: time,
                    routePoint: p,
                    preferredLeadingSide: km % 2 == 0
                )
            )
        }
        return markers
    }
}
#endif
