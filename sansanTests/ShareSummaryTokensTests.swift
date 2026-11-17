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
        XCTAssertEqual(ShareSummaryTokens.headerBottom(memoLineCount: 0), 104, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.headerBottom(memoLineCount: 1), 129, accuracy: 0.01)
        XCTAssertEqual(ShareSummaryTokens.headerBottom(memoLineCount: 3), 163, accuracy: 0.01)
    }

    func testMapInsetsIncludeMarkerRadius() {
        let top = ShareSummaryTokens.mapTopInset(memoLineCount: 0)
        XCTAssertEqual(top, 104 + 16 + 9, accuracy: 0.01)
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
        XCTAssertEqual(ShareSummaryTokens.attributionClearZone, 4, accuracy: 0.01)
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

    func testDetailMapBlueLabelTokens() {
        XCTAssertEqual(RouteKilometerMarkerMetrics.detailLabelHideSteps, [1, 5, 10, 20, 50])
        XCTAssertEqual(RouteKilometerMarkerMetrics.detailLabelSideInset, 24, accuracy: 0.01)
        XCTAssertEqual(RouteKilometerMarkerMetrics.detailLabelVerticalInset, 8, accuracy: 0.01)
        XCTAssertEqual(RouteKilometerMarkerMetrics.detailLabelStrokeWidth, 1, accuracy: 0.01)
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

    func testDetailThinningHidesLowPriorityIndividually() {
        // Tall-enough for one capsule only (h24 + y inset 8→8): vertical nudges clip.
        // Right-edge x: trailing side clips. 10× places first; 1·2 hide individually.
        let canvas = CGSize(width: 390, height: 40)
        let edge = CGPoint(x: 360, y: 20)
        let requests = [
            RouteKilometerLabelRequest(
                kilometer: 1,
                distanceLabel: "1km",
                timeLabel: "10:00",
                routePoint: edge,
                preferredLeadingSide: true
            ),
            RouteKilometerLabelRequest(
                kilometer: 2,
                distanceLabel: "2km",
                timeLabel: "20:00",
                routePoint: CGPoint(x: 361, y: 20),
                preferredLeadingSide: true
            ),
            RouteKilometerLabelRequest(
                kilometer: 10,
                distanceLabel: "10km",
                timeLabel: "1:40:00",
                routePoint: edge,
                preferredLeadingSide: true
            )
        ]
        let thinned = RouteKilometerMarkerDrawing.thinnedDetailLabelShifts(
            for: requests,
            endpointPoints: [CGPoint(x: 40, y: 20), CGPoint(x: 200, y: 20)],
            contentScale: 1,
            imageSize: canvas
        )
        XCTAssertEqual(thinned.step, 1, "must not wholesale-escalate hideSteps")
        XCTAssertEqual(Set(thinned.shifts.keys), Set([10]), "only 10× kept; 1·2 hidden one-by-one")
    }

    func testDetailThinningIgnoresOffscreenPointsSoZoomInKeepsVisibleLabels() {
        // Short record 1–4: one off-screen point must not wipe on-screen 1km labels (JW zoom-in bug).
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
        let thinned = RouteKilometerMarkerDrawing.thinnedDetailLabelShifts(
            for: requests,
            endpointPoints: [CGPoint(x: 40, y: 160), CGPoint(x: 340, y: 240)],
            contentScale: 1,
            imageSize: canvas
        )
        XCTAssertFalse(thinned.shifts.isEmpty, "visible 1–3 must still get labels")
        XCTAssertTrue(thinned.shifts.keys.contains(1))
        XCTAssertFalse(thinned.shifts.keys.contains(4), "off-screen km must not be labeled")
    }

    func testDetailLabelKeepPriorityOrder() {
        XCTAssertEqual(RouteKilometerMarkerDrawing.detailLabelKeepPriority(10), 2)
        XCTAssertEqual(RouteKilometerMarkerDrawing.detailLabelKeepPriority(20), 2)
        XCTAssertEqual(RouteKilometerMarkerDrawing.detailLabelKeepPriority(5), 1)
        XCTAssertEqual(RouteKilometerMarkerDrawing.detailLabelKeepPriority(15), 1)
        XCTAssertEqual(RouteKilometerMarkerDrawing.detailLabelKeepPriority(1), 0)
        XCTAssertEqual(RouteKilometerMarkerDrawing.detailLabelKeepPriority(7), 0)
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
}
