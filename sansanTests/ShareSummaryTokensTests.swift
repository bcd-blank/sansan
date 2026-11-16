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
