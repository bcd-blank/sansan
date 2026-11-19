//
//  ShareSummaryTokensTests.swift
//  sansanTests
//

import XCTest
@testable import sansan

final class ShareSummaryTokensTests: XCTestCase {
    func testCanvasAspectIsSixteenByNine() {
        XCTAssertEqual(ShareSummaryTokens.canvasWidth, 430, accuracy: 0.001)
        XCTAssertEqual(ShareSummaryTokens.canvasAspect, 16.0 / 9.0, accuracy: 0.0001)
    }

    func testCanvasHeightCeilsPixelAspect() {
        // 1290 × 16/9 = 2293.33 → 2294 (S8)
        let size = ShareSummaryTokens.canvasSize(widthPoints: 430, pixelScale: 3)
        XCTAssertEqual(size.width, 430, accuracy: 0.001)
        XCTAssertEqual(size.height * 3, 2294, accuracy: 0.001)
    }

    func testCardHeightMatchesDesignerSum() {
        XCTAssertEqual(ShareSummaryTokens.cardHeight, 324.5, accuracy: 0.01)
    }

    func testKmLabelTokensSharedWithMarkerMetrics() {
        XCTAssertEqual(ShareSummaryTokens.kmDot, RouteKilometerMarkerMetrics.routeDotDiameter)
        XCTAssertEqual(ShareSummaryTokens.kmDotStroke, RouteKilometerMarkerMetrics.routeDotBorderWidth)
        XCTAssertEqual(ShareSummaryTokens.kmLabelHeight, RouteKilometerMarkerMetrics.labelHeight)
        XCTAssertEqual(ShareSummaryTokens.kmLabelPadH, RouteKilometerMarkerMetrics.labelPadH)
        XCTAssertEqual(ShareSummaryTokens.kmLabelGap, RouteKilometerMarkerMetrics.combinedInnerGap)
        XCTAssertEqual(ShareSummaryTokens.kmLabelOffset, RouteKilometerMarkerMetrics.labelGap)
        XCTAssertEqual(ShareSummaryTokens.kmLabelFont, RouteKilometerMarkerMetrics.labelFontSize)
        XCTAssertEqual(RouteKilometerMarkerMetrics.routeDotDiameter, 10, accuracy: 0.01)
        XCTAssertEqual(RouteKilometerMarkerMetrics.labelGap, 10, accuracy: 0.01)
    }

    func testCombinedLabelCases() {
        XCTAssertEqual(
            RouteKilometerMarkerMetrics.combinedLabel(distance: "1km", time: "16:50"),
            "1km 16:50"
        )
        XCTAssertEqual(
            RouteKilometerMarkerMetrics.combinedLabel(distance: "1km", time: nil),
            "1km"
        )
        XCTAssertEqual(
            RouteKilometerMarkerMetrics.combinedLabel(distance: nil, time: "16:50"),
            "16:50"
        )
        XCTAssertNil(RouteKilometerMarkerMetrics.combinedLabel(distance: nil, time: nil))
    }

    func testMemoHeaderBottoms() {
        // Android ShareSummaryTokens.HEADER_BOTTOM_NONE/1/3 — memo height 0 when absent.
        XCTAssertEqual(ShareSummaryTokens.headerBottom(memoLineCount: 0), 104, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.headerBottom(memoLineCount: 1), 129, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.headerBottom(memoLineCount: 3), 163, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.memoLineCount(nil, canvasWidth: 430), 0)
        XCTAssertEqual(ShareSummaryTokens.memoLineCount("  ", canvasWidth: 430), 0)
        XCTAssertEqual(ShareSummaryTokens.titleLabelMinGap, 10, accuracy: 0.01)
    }

    func testTitleLabelMinGapRejectsCandidatesInForbiddenBand() {
        // Dot just below title bottom; upward/near-title candidates must clear +10pt gap.
        let titleBottom: CGFloat = ShareSummaryTokens.headerBottom(memoLineCount: 0)
        let request = RouteKilometerLabelRequest(
            kilometer: 1,
            distanceLabel: "1km",
            timeLabel: "13:55",
            routePoint: CGPoint(x: 120, y: titleBottom + 28),
            preferredLeadingSide: false
        )
        let previousBudget = RouteKilometerLabelPlacement.softTimeBudgetSeconds
        RouteKilometerLabelPlacement.softTimeBudgetSeconds = 2.0
        defer { RouteKilometerLabelPlacement.softTimeBudgetSeconds = previousBudget }
        let result = RouteKilometerLabelPlacement.placeSummary(
            markers: [request],
            endpointPoints: [CGPoint(x: 80, y: titleBottom + 40), CGPoint(x: 300, y: 400)],
            routePolyline: [
                CGPoint(x: 80, y: titleBottom + 40),
                CGPoint(x: 120, y: titleBottom + 28),
                CGPoint(x: 200, y: titleBottom + 80)
            ],
            contentScale: 1,
            imageSize: CGSize(width: 430, height: 764),
            sideInset: 24,
            titleBlockBottom: titleBottom
        )
        XCTAssertFalse(result.shifts.isEmpty)
        let shift = try! XCTUnwrap(result.shifts[1])
        let size = RouteKilometerMarkerDrawing.capsuleSize(
            distanceLabel: "1km",
            timeLabel: "13:55",
            contentScale: 1
        )
        let centerY = request.routePoint.y + shift.centerOffset.y
        let boxTop = centerY - size.height / 2
        let minTop = titleBottom + ShareSummaryTokens.titleLabelMinGap
        XCTAssertGreaterThanOrEqual(
            boxTop,
            minTop - 0.5,
            "1km box top \(boxTop) must clear titleBottom+gap \(minTop)"
        )
    }

    func testMapInsetsIncludeMarkerRadius() {
        // Route fit top = title bottom (104) + routeClearance (16). Side/bottom still use marker pad.
        let top = ShareSummaryTokens.mapTopInset(memoLineCount: 0)
        XCTAssertEqual(top, 104 + 16, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.mapBottomInset, 324.5 + 32 + 9, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.mapSideInset, 24, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.mapMarkerInsetPad, 9, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.mapRouteSideInset, 33, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.kmLabelBoundsInset, 24, accuracy: 0.01)
    }

    func testTimelineTokens() {
        XCTAssertEqual(ShareSummaryTokens.timelineDotX, 284, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.timelineDotSpacing, 56, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.metricUnitGap, 2, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.metricUnitTrailing, 6, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.metricMinScale, 0.82, accuracy: 0.001)
        XCTAssertEqual(ShareSummaryTokens.cardLabelGap, 4, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.attributionFontSize, 10, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.attributionLogoHeight, 9, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.attributionLineHeight, 12, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.attributionClearZone, 0, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.memoLineHeight, 17, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.weatherIconSize, 18, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.graphElevWidth, 1, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.graphHRWidth, 1, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.chartElevFillAlpha, 0.15, accuracy: 0.001)
        XCTAssertEqual(ShareSummaryTokens.ColorHex.chartElev, "FF8D28")
        XCTAssertEqual(ShareSummaryTokens.ColorHex.chartHR, "FF383C")
        XCTAssertEqual(ShareSummaryTokens.graphLegendElevHeight, 1, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.graphLegendHRHeight, 1, accuracy: 0.01)
    }

    func testLiveDetailLabelScaleMatchesSummary65pxBand() {
        let scale = RouteKilometerMarkerMetrics.liveDetailLabelContentScale
        // Layout height 68px @3x → measured fill AABB lands on Simple's 65±1.
        let layoutHeightPx = RouteKilometerMarkerMetrics.labelHeight * scale * 3
        XCTAssertEqual(layoutHeightPx, 68, accuracy: 0.01)
        XCTAssertEqual(RouteKilometerMarkerMetrics.labelStrokeWidth, 0.5, accuracy: 0.01)
    }

    func testDetailMapBlueLabelTokens() {
        XCTAssertEqual(RouteKilometerMarkerMetrics.detailLabelHideSteps, [1, 5, 10, 20, 50])
        XCTAssertEqual(RouteKilometerMarkerMetrics.detailLabelSideInset, 24, accuracy: 0.01)
        XCTAssertEqual(RouteKilometerMarkerMetrics.detailLabelVerticalInset, 8, accuracy: 0.01)
        // Detail stroke aliases Simple — geometry shared; color only differs.
        XCTAssertEqual(RouteKilometerMarkerMetrics.labelStrokeWidth, 0.5, accuracy: 0.01)
        XCTAssertEqual(
            RouteKilometerMarkerMetrics.detailLabelStrokeWidth,
            RouteKilometerMarkerMetrics.labelStrokeWidth,
            accuracy: 0.01
        )
        XCTAssertEqual(
            RouteKilometerMarkerMetrics.labelCornerRadius,
            RouteKilometerMarkerMetrics.labelHeight / 2,
            accuracy: 0.01
        )
        XCTAssertEqual(RouteKilometerMarkerMetrics.distanceLabelWeight, .semibold)
        XCTAssertEqual(RouteKilometerMarkerMetrics.timeLabelWeight(hasDistance: true), .regular)
        XCTAssertEqual(RouteKilometerMarkerMetrics.timeLabelWeight(hasDistance: false), .medium)
        XCTAssertEqual(
            RouteKilometerMarkerMetrics.detailTimeLabelWeight(hasDistance: true),
            RouteKilometerMarkerMetrics.timeLabelWeight(hasDistance: true)
        )
        let whiteSize = RouteKilometerMarkerDrawing.capsuleSize(
            distanceLabel: "1km",
            timeLabel: "16:50",
            contentScale: 1
        )
        XCTAssertEqual(whiteSize.height, RouteKilometerMarkerMetrics.labelHeight, accuracy: 0.01)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        RouteKilometerMarkerMetrics.detailLabelFillUIColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r * 255, 0, accuracy: 0.5)
        XCTAssertEqual(g * 255, 122, accuracy: 0.5)
        XCTAssertEqual(b * 255, 255, accuracy: 0.5)
        XCTAssertEqual(a, 1, accuracy: 0.01)
    }

    func testDetailPlacementEscalatesToFiveKmWhenOneKmCannotClear() {
        // Narrow band: 1+2+5 packed so 1km fails → wholesale 5km (F1) when 5 exists.
        let canvas = CGSize(width: 390, height: 80)
        let requests = [
            RouteKilometerLabelRequest(
                kilometer: 1,
                distanceLabel: "1km",
                timeLabel: "10:00",
                routePoint: CGPoint(x: 180, y: 40),
                preferredLeadingSide: true
            ),
            RouteKilometerLabelRequest(
                kilometer: 2,
                distanceLabel: "2km",
                timeLabel: "20:00",
                routePoint: CGPoint(x: 188, y: 40),
                preferredLeadingSide: true
            ),
            RouteKilometerLabelRequest(
                kilometer: 5,
                distanceLabel: "5km",
                timeLabel: "50:00",
                routePoint: CGPoint(x: 196, y: 40),
                preferredLeadingSide: true
            )
        ]
        let placed = RouteKilometerMarkerDrawing.thinnedDetailLabelShifts(
            for: requests,
            endpointPoints: [CGPoint(x: 40, y: 40), CGPoint(x: 350, y: 40)],
            contentScale: 1,
            imageSize: canvas,
            zoomDelta: 1
        )
        XCTAssertFalse(placed.shifts.isEmpty)
        if placed.modeStep >= 5 {
            XCTAssertFalse(placed.shifts.keys.contains(1))
            XCTAssertFalse(placed.shifts.keys.contains(2))
            XCTAssertTrue(placed.shifts.keys.contains(5))
        }
    }

    func testDetailPlacementIgnoresOffscreenPointsSoZoomInKeepsVisibleLabels() {
        // Short record 1–4: off-screen 4km must not force empty on-screen labels (TC-01/TC-13).
        let canvas = CGSize(width: 390, height: 400)
        let requests = [
            RouteKilometerLabelRequest(
                kilometer: 1,
                distanceLabel: "1km",
                timeLabel: "10:00",
                routePoint: CGPoint(x: 120, y: 180),
                preferredLeadingSide: false
            ),
            RouteKilometerLabelRequest(
                kilometer: 2,
                distanceLabel: "2km",
                timeLabel: "20:00",
                routePoint: CGPoint(x: 200, y: 200),
                preferredLeadingSide: false
            ),
            RouteKilometerLabelRequest(
                kilometer: 3,
                distanceLabel: "3km",
                timeLabel: "30:00",
                routePoint: CGPoint(x: 280, y: 220),
                preferredLeadingSide: true
            ),
            RouteKilometerLabelRequest(
                kilometer: 4,
                distanceLabel: "4km",
                timeLabel: "40:00",
                routePoint: CGPoint(x: -80, y: 200), // off-screen after zoom-in
                preferredLeadingSide: false
            )
        ]
        XCTAssertFalse(
            RouteKilometerMarkerDrawing.isDetailMarkerOnScreen(requests[3].routePoint, imageSize: canvas)
        )
        let placed = RouteKilometerMarkerDrawing.thinnedDetailLabelShifts(
            for: requests,
            endpointPoints: [CGPoint(x: 40, y: 160), CGPoint(x: 340, y: 240)],
            contentScale: 1,
            imageSize: canvas,
            zoomDelta: 1
        )
        XCTAssertEqual(placed.modeStep, 1)
        XCTAssertTrue(placed.shifts.keys.contains(1))
        XCTAssertTrue(placed.shifts.keys.contains(2))
        XCTAssertTrue(placed.shifts.keys.contains(3))
        XCTAssertFalse(placed.shifts.keys.contains(4), "off-screen km must not be labeled")
    }

    func testDetailF5KeepsPartialWhenNoFiveKmOnScreen() {
        // <5km record packed on a short canvas → F5 partial, not empty (JW ③ / TC-12).
        let canvas = CGSize(width: 280, height: 72)
        let requests = (1...4).map { km in
            RouteKilometerLabelRequest(
                kilometer: km,
                distanceLabel: "\(km)km",
                timeLabel: "1\(km):00",
                routePoint: CGPoint(x: 120 + CGFloat(km) * 3, y: 36),
                preferredLeadingSide: false
            )
        }
        let placed = RouteKilometerMarkerDrawing.thinnedDetailLabelShifts(
            for: requests,
            endpointPoints: [CGPoint(x: 30, y: 36), CGPoint(x: 250, y: 36)],
            contentScale: 1,
            imageSize: canvas,
            zoomDelta: 1
        )
        XCTAssertEqual(placed.modeStep, 1)
        XCTAssertFalse(placed.shifts.isEmpty, "F5 must show placeable labels when no 5km point exists")
    }

    func testPlacementIdleBudgetUnder300msForMountainScenes() {
        // JW: camera idle → labels visible ≤ 300ms (same bar as Android).
        let canvas = CGSize(width: 390, height: 700)
        let scenes: [(String, Int, CGFloat)] = [
            ("saryangdo", 8, 34),
            ("gahyeonsan", 3, 70),
            ("samaksan", 6, 48)
        ]
        var lines: [String] = []
        for (name, count, spacing) in scenes {
            let requests = (1...count).map { km in
                RouteKilometerLabelRequest(
                    kilometer: km,
                    distanceLabel: "\(km)km",
                    timeLabel: String(format: "%d:%02d", km, km * 7 % 60),
                    routePoint: CGPoint(
                        x: 70 + CGFloat(km) * spacing,
                        y: 160 + CGFloat(km % 3) * 36
                    ),
                    preferredLeadingSide: km % 2 == 0
                )
            }
            let poly = requests.map(\.routePoint)
            let summary = RouteKilometerLabelPlacement.placeSummary(
                markers: requests,
                endpointPoints: [CGPoint(x: 40, y: 120), CGPoint(x: 360, y: 320)],
                routePolyline: poly,
                contentScale: 1,
                imageSize: canvas,
                sideInset: 24
            )
            let detail = RouteKilometerLabelPlacement.placeDetail(
                markers: requests,
                endpointPoints: [CGPoint(x: 40, y: 120), CGPoint(x: 360, y: 320)],
                routePolyline: poly,
                contentScale: 1,
                imageSize: canvas,
                preferModeStep: 1,
                zoomDelta: 1
            )
            lines.append(
                "summary-\(name) \(Int(summary.elapsedMilliseconds.rounded()))ms mode=\(summary.modeStep) stage=\(summary.stageName) nodes=\(summary.nodesVisited) labels=\(summary.shifts.count)"
            )
            lines.append(
                "detail-\(name) \(Int(detail.elapsedMilliseconds.rounded()))ms mode=\(detail.modeStep) stage=\(detail.stageName) nodes=\(detail.nodesVisited) labels=\(detail.shifts.count)"
            )
            XCTAssertLessThan(summary.elapsedMilliseconds, 300, lines.last!)
            XCTAssertLessThan(detail.elapsedMilliseconds, 300, lines.last!)
            XCTAssertFalse(summary.shifts.isEmpty)
            XCTAssertFalse(detail.shifts.isEmpty)
        }
        let text = (["budget=300ms softSolver=280ms keepPreviousLabels=true"] + lines).joined(separator: "\n") + "\n"
        let outPaths = [
            URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("km-label-LATENCY.txt"),
            URL(fileURLWithPath: "/Users/jeongwook/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-75707dba-5737-4d43-b5ab-a5deda5241a4/files/docs/label-placement/final/impl-ios/LATENCY.txt")
        ]
        for url in outPaths {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
        NSLog("%@", "[km-label-latency]\n\(text)")
    }

    func testDetailLabelKeepPriorityScaffoldStillAvailable() {
        // Inactive per-label path kept for a future designer spec.
        XCTAssertEqual(RouteKilometerMarkerDrawing.detailLabelKeepPriority(10), 2)
        XCTAssertEqual(RouteKilometerMarkerDrawing.detailLabelKeepPriority(5), 1)
        XCTAssertEqual(RouteKilometerMarkerDrawing.detailLabelKeepPriority(1), 0)
    }

    func testKmLabelCanvasClampPrefersInBoundsSide() throws {
        // Dot near right edge of 430pt canvas — right-side capsule would clip past 430.
        let canvas = CGSize(width: 430, height: 764)
        let request = RouteKilometerLabelRequest(
            kilometer: 3,
            distanceLabel: "3km",
            timeLabel: "1:30:55",
            routePoint: CGPoint(x: 400, y: 240),
            preferredLeadingSide: false
        )
        let shifts = RouteKilometerMarkerDrawing.labelShifts(
            for: [request],
            endpointPoints: [CGPoint(x: 33, y: 240), CGPoint(x: 406, y: 240)],
            contentScale: 1,
            imageSize: canvas,
            sideInset: ShareSummaryTokens.kmLabelBoundsInset
        )
        let shift = try XCTUnwrap(shifts[3])
        XCTAssertTrue(shift.placesLabelOnLeadingSide, "right-edge 3km must flip to leading/left")
        let size = RouteKilometerMarkerDrawing.capsuleSize(
            distanceLabel: "3km",
            timeLabel: "1:30:55",
            contentScale: 1
        )
        let gap = RouteKilometerMarkerMetrics.labelGap
        let centerX = request.routePoint.x - (gap + size.width / 2)
        let left = centerX - size.width / 2
        let right = centerX + size.width / 2
        XCTAssertGreaterThanOrEqual(left, ShareSummaryTokens.kmLabelBoundsInset - 0.5)
        XCTAssertLessThanOrEqual(right, canvas.width - ShareSummaryTokens.kmLabelBoundsInset + 0.5)
    }

    func testMaxMemoLengthIs200() {
        XCTAssertEqual(SavedHikingSession.maxMemoLength, 200)
    }

    /// 행주나루길 loop: 3km sits near start/end. Endpoint ownMargin must not drop it
    /// (Android aloneOk hard-clears endpoints only) — Simple Grey/Color parity.
    func testHangjunaruPlaceSummaryKeepsThreeKmNearEndpoints() throws {
        let fixture = URL(fileURLWithPath:
            "/Users/jeongwook/Documents/sansan-보관/작업복사본-iOS/sansan-ios-detail-label-zoom-e75c/sansan/Resources/uitest-fixtures/hangjunaru.json"
        )
        let data = try Data(contentsOf: fixture)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(SavedHikingSession.self, from: data)
        let coords = record.session.points.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        XCTAssertGreaterThanOrEqual(coords.count, 2)

        let canvas = ShareSummaryTokens.canvasSize(widthPoints: 402, pixelScale: 1)
        let memoLines = 0
        let region = HikingMapRegion.fitting(
            coordinates: coords,
            viewSize: canvas,
            insetTop: ShareSummaryTokens.mapTopInset(memoLineCount: memoLines),
            insetLeft: ShareSummaryTokens.mapRouteSideInset,
            insetBottom: ShareSummaryTokens.mapBottomInset,
            insetRight: ShareSummaryTokens.mapRouteSideInset,
            verticalAlign: .top
        )
        func project(_ c: CLLocationCoordinate2D) -> CGPoint {
            HikingMapRegion.point(for: c, in: region, canvasSize: canvas)
        }

        let markers = HikingSessionMetrics.kilometerMarkerPlacements(from: record.session.points)
        let times = HikingSessionMetrics.kilometerArrivalElapsedLabels(
            from: record.session.points,
            startedAt: record.session.effectiveStartedAt,
            segmentBreaks: record.session.segmentBreaks
        )
        let requests: [RouteKilometerLabelRequest] = markers.map { marker in
            RouteKilometerLabelRequest(
                kilometer: marker.kilometer,
                distanceLabel: marker.labelText,
                timeLabel: times[marker.kilometer],
                routePoint: project(marker.coordinate),
                preferredLeadingSide: marker.placesLabelOnLeadingSide
            )
        }
        XCTAssertEqual(Set(requests.map(\.kilometer)), Set([1, 2, 3]))

        var endpoints: [CGPoint] = [project(coords[0])]
        if coords.count > 1 { endpoints.append(project(coords[coords.count - 1])) }
        let poly = coords.map(project)
        let contentScale = RouteKilometerMarkerMetrics.labelContentScale(forWidth: canvas.width)
        let titleBottom = ShareSummaryTokens.headerBottom(memoLineCount: memoLines) * contentScale

        let previousBudget = RouteKilometerLabelPlacement.softTimeBudgetSeconds
        RouteKilometerLabelPlacement.softTimeBudgetSeconds = 2.0
        defer { RouteKilometerLabelPlacement.softTimeBudgetSeconds = previousBudget }

        let placed = RouteKilometerLabelPlacement.placeSummary(
            markers: requests,
            endpointPoints: endpoints,
            routePolyline: poly,
            contentScale: contentScale,
            imageSize: canvas,
            sideInset: ShareSummaryTokens.kmLabelBoundsInset * contentScale,
            pathHalfWidth: ShareSummaryTokens.routeCasing / 2,
            titleBlockBottom: titleBottom
        )
        XCTAssertEqual(
            Set(placed.shifts.keys),
            Set([1, 2, 3]),
            "hangjunaru Simple must keep 3km near loop endpoints; stage=\(placed.stageName) partial=\(placed.partial) keys=\(placed.shifts.keys.sorted())"
        )
    }
}
