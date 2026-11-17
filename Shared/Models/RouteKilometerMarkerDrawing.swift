//
//  RouteKilometerMarkerDrawing.swift
//  Shared
//
//  Combined km/time capsules for share summary / card / flythrough (white)
//  plus detail-map thinning helpers (blue capsules live in SwiftUI markers).
//

#if os(iOS)

import UIKit

enum RouteKilometerMarkerDrawing {
    /// 시작·종료 점(지름 18) 밖으로 라벨을 띄우는 여유.
    private static let endpointClearanceRadius: CGFloat = 18 / 2 + 6

    /// Share-summary / card: final-spec v3 placement (16 dirs + aligned, rings A–D).
    static func labelShifts(
        for markers: [RouteKilometerLabelRequest],
        endpointPoints: [CGPoint],
        contentScale: CGFloat,
        imageSize: CGSize = .zero,
        sideInset: CGFloat = 0,
        routePolyline: [CGPoint] = [],
        pathHalfWidth: CGFloat = ShareSummaryTokens.routeCasing / 2
    ) -> [Int: RouteKilometerLabelShift] {
        guard !markers.isEmpty else { return [:] }
        let size = imageSize.width > 1 ? imageSize : CGSize(width: 2000, height: 2000)
        let result = RouteKilometerLabelPlacement.placeSummary(
            markers: markers,
            endpointPoints: endpointPoints,
            routePolyline: routePolyline,
            contentScale: contentScale,
            imageSize: size,
            sideInset: sideInset,
            pathHalfWidth: pathHalfWidth
        )
        if !result.shifts.isEmpty { return result.shifts }
        // Extreme fallback: legacy L/R nudges so drawing never blanks all labels.
        return legacyLabelShifts(
            for: markers,
            endpointPoints: endpointPoints,
            contentScale: contentScale,
            imageSize: imageSize,
            sideInset: sideInset
        )
    }

    /// Detail-map: final-spec v3 + F1–F5 (visible-only, wholesale 1→5, F5 partial).
    static func thinnedDetailLabelShifts(
        for markers: [RouteKilometerLabelRequest],
        endpointPoints: [CGPoint],
        contentScale: CGFloat,
        imageSize: CGSize,
        sideInset: CGFloat = RouteKilometerMarkerMetrics.detailLabelSideInset,
        verticalInset: CGFloat = RouteKilometerMarkerMetrics.detailLabelVerticalInset,
        routePolyline: [CGPoint] = [],
        preferModeStep: Int = 1,
        zoomDelta: Double = 1, // treat first layout like a zoom change → start at 1km
        pathHalfWidth: CGFloat = 4
    ) -> RouteKilometerPlacementResult {
        _ = sideInset
        _ = verticalInset
        return RouteKilometerLabelPlacement.placeDetail(
            markers: markers,
            endpointPoints: endpointPoints,
            routePolyline: routePolyline,
            contentScale: contentScale,
            imageSize: imageSize,
            preferModeStep: preferModeStep,
            zoomDelta: zoomDelta,
            pathHalfWidth: pathHalfWidth
        )
    }

    /// Km-dot center inside the map view — off-screen points are excluded from thinning.
    static func isDetailMarkerOnScreen(_ point: CGPoint, imageSize: CGSize) -> Bool {
        RouteKilometerLabelPlacement.isOnScreen(point, size: imageSize)
    }

    /// Legacy sequential L/R placement (fallback only).
    private static func legacyLabelShifts(
        for markers: [RouteKilometerLabelRequest],
        endpointPoints: [CGPoint],
        contentScale: CGFloat,
        imageSize: CGSize,
        sideInset: CGFloat
    ) -> [Int: RouteKilometerLabelShift] {
        var occupied: [CGRect] = []
        var shifts: [Int: RouteKilometerLabelShift] = [:]
        for marker in markers {
            let placed = bestShift(
                distanceLabel: marker.distanceLabel,
                timeLabel: marker.timeLabel,
                routePoint: marker.routePoint,
                preferredLeadingSide: marker.preferredLeadingSide,
                endpointPoints: endpointPoints,
                occupied: occupied,
                contentScale: contentScale,
                imageSize: imageSize,
                sideInset: sideInset,
                requireClear: false
            )
            shifts[marker.kilometer] = placed.shift
            occupied.append(contentsOf: placed.rects)
        }
        return shifts
    }

    /// Inactive (JW): per-label hide with keep priority 10× → 5× → rest.
    /// Kept for a future designer-confirmed spec; not used by `thinnedDetailLabelShifts`.
    static func detailLabelKeepPriority(_ kilometer: Int) -> Int {
        if kilometer % 10 == 0 { return 2 }
        if kilometer % 5 == 0 { return 1 }
        return 0
    }

    /// Inactive scaffold: individual label hide (not the live detail path).
    static func thinnedDetailLabelShiftsPerLabelHide(
        for markers: [RouteKilometerLabelRequest],
        endpointPoints: [CGPoint],
        contentScale: CGFloat,
        imageSize: CGSize,
        sideInset: CGFloat = RouteKilometerMarkerMetrics.detailLabelSideInset,
        verticalInset: CGFloat = RouteKilometerMarkerMetrics.detailLabelVerticalInset
    ) -> [Int: RouteKilometerLabelShift] {
        let visible = markers.filter { isDetailMarkerOnScreen($0.routePoint, imageSize: imageSize) }
        guard !visible.isEmpty else { return [:] }
        let ordered = visible.sorted { lhs, rhs in
            let lp = detailLabelKeepPriority(lhs.kilometer)
            let rp = detailLabelKeepPriority(rhs.kilometer)
            if lp != rp { return lp > rp }
            return lhs.kilometer < rhs.kilometer
        }
        var occupied: [CGRect] = []
        var shifts: [Int: RouteKilometerLabelShift] = [:]
        for marker in ordered {
            let placed = bestShift(
                distanceLabel: marker.distanceLabel,
                timeLabel: marker.timeLabel,
                routePoint: marker.routePoint,
                preferredLeadingSide: marker.preferredLeadingSide,
                endpointPoints: endpointPoints,
                occupied: occupied,
                contentScale: contentScale,
                imageSize: imageSize,
                sideInset: sideInset,
                requireClear: true,
                verticalInset: verticalInset
            )
            guard let clear = placed.clear else { continue }
            shifts[marker.kilometer] = clear.shift
            occupied.append(contentsOf: clear.rects)
        }
        return shifts
    }

    /// Places every marker only when each capsule is clear of labels, endpoints, and inset bounds.
    private static func labelShiftsClear(
        for markers: [RouteKilometerLabelRequest],
        endpointPoints: [CGPoint],
        contentScale: CGFloat,
        imageSize: CGSize,
        sideInset: CGFloat,
        verticalInset: CGFloat
    ) -> [Int: RouteKilometerLabelShift]? {
        var occupied: [CGRect] = []
        var shifts: [Int: RouteKilometerLabelShift] = [:]
        for marker in markers {
            let placed = bestShift(
                distanceLabel: marker.distanceLabel,
                timeLabel: marker.timeLabel,
                routePoint: marker.routePoint,
                preferredLeadingSide: marker.preferredLeadingSide,
                endpointPoints: endpointPoints,
                occupied: occupied,
                contentScale: contentScale,
                imageSize: imageSize,
                sideInset: sideInset,
                requireClear: true,
                verticalInset: verticalInset
            )
            guard let clear = placed.clear else { return nil }
            shifts[marker.kilometer] = clear.shift
            occupied.append(contentsOf: clear.rects)
        }
        return shifts
    }

    private static func bestShift(
        distanceLabel: String?,
        timeLabel: String?,
        routePoint: CGPoint,
        preferredLeadingSide: Bool,
        endpointPoints: [CGPoint],
        occupied: [CGRect],
        contentScale: CGFloat,
        imageSize: CGSize,
        sideInset: CGFloat,
        requireClear: Bool,
        verticalInset: CGFloat = 0
    ) -> (
        shift: RouteKilometerLabelShift,
        rects: [CGRect],
        clear: (shift: RouteKilometerLabelShift, rects: [CGRect])?
    ) {
        let clearance = endpointClearanceRadius * contentScale
        let labelPadding = requireClear
            ? RouteKilometerMarkerMetrics.detailLabelCollisionPad * contentScale
            : 3 * contentScale
        let unit = max(RouteKilometerMarkerMetrics.labelHeight * contentScale, 12 * contentScale)
        // Preferred side first, then opposite / vertical nudges. Canvas clamp rejects clips (impl4 #2).
        let nudges: [(sideIsPreferred: Bool, multiplier: CGFloat)] = [
            (true, 0),
            (false, 0),
            (true, 1),
            (false, 1),
            (true, -1),
            (false, -1),
            (true, 1.6),
            (false, 1.6),
            (true, -1.6),
            (false, -1.6)
        ]

        var bestShift = RouteKilometerLabelShift(
            placesLabelOnLeadingSide: preferredLeadingSide,
            verticalOffset: 0
        )
        var bestRects = labelRects(
            distanceLabel: distanceLabel,
            timeLabel: timeLabel,
            routePoint: routePoint,
            placesLabelOnLeadingSide: preferredLeadingSide,
            verticalOffset: 0,
            contentScale: contentScale
        )
        var bestPenalty = CGFloat.greatestFiniteMagnitude
        var foundInBounds = false
        var clearPlacement: (shift: RouteKilometerLabelShift, rects: [CGRect])?

        for (index, nudge) in nudges.enumerated() {
            let side = nudge.sideIsPreferred ? preferredLeadingSide : !preferredLeadingSide
            let verticalOffset = unit * nudge.multiplier
            let rects = labelRects(
                distanceLabel: distanceLabel,
                timeLabel: timeLabel,
                routePoint: routePoint,
                placesLabelOnLeadingSide: side,
                verticalOffset: verticalOffset,
                contentScale: contentScale
            )
            // Hard-reject capsules that leave the image (review #2).
            if clipsCanvas(rects, imageSize: imageSize) { continue }
            let boundsHit = imageBoundsPenalty(
                rects,
                imageSize: imageSize,
                sideInset: sideInset,
                verticalInset: verticalInset
            )
            let endpointScore = endpointSeparation(of: rects, from: endpointPoints, clearance: clearance)
            let overlapsLabels = rectsOverlap(rects, occupied, padding: labelPadding)
            let endpointPenalty: CGFloat = endpointScore == .greatestFiniteMagnitude ? 0 : -endpointScore * 48
            let clear = endpointScore == .greatestFiniteMagnitude && !overlapsLabels && boundsHit < 1
            let penalty = overlapArea(rects, occupied)
                + endpointPenalty
                + boundsHit
                + abs(nudge.multiplier) * 2
                + CGFloat(index) * 0.4
                + (clear ? 0 : 80)
            if penalty < bestPenalty {
                bestPenalty = penalty
                bestShift = RouteKilometerLabelShift(
                    placesLabelOnLeadingSide: side,
                    verticalOffset: verticalOffset
                )
                bestRects = rects
                foundInBounds = true
                if clear {
                    let placement = (bestShift, bestRects)
                    if requireClear {
                        return (bestShift, bestRects, placement)
                    }
                    clearPlacement = placement
                    return (bestShift, bestRects, placement)
                }
            }
        }
        if requireClear {
            return (bestShift, bestRects, nil)
        }
        if foundInBounds {
            return (bestShift, bestRects, clearPlacement)
        }
        // Last resort: flip to leading (left) so a right-edge clip still paints on-canvas.
        let fallbackSide = true
        let fallbackRects = labelRects(
            distanceLabel: distanceLabel,
            timeLabel: timeLabel,
            routePoint: routePoint,
            placesLabelOnLeadingSide: fallbackSide,
            verticalOffset: 0,
            contentScale: contentScale
        )
        if !clipsCanvas(fallbackRects, imageSize: imageSize) {
            let fallback = RouteKilometerLabelShift(placesLabelOnLeadingSide: fallbackSide, verticalOffset: 0)
            return (fallback, fallbackRects, nil)
        }
        return (bestShift, bestRects, nil)
    }

    private static func clipsCanvas(_ rects: [CGRect], imageSize: CGSize) -> Bool {
        guard imageSize.width > 1, imageSize.height > 1 else { return false }
        return rects.contains { rect in
            rect.minX < -0.5
                || rect.maxX > imageSize.width + 0.5
                || rect.minY < -0.5
                || rect.maxY > imageSize.height + 0.5
        }
    }

    /// Heavy penalty when capsule leaves the inset band.
    /// Detail map: x [sideInset, W−sideInset], y [verticalInset, H−verticalInset].
    private static func imageBoundsPenalty(
        _ rects: [CGRect],
        imageSize: CGSize,
        sideInset: CGFloat,
        verticalInset: CGFloat = 0
    ) -> CGFloat {
        guard imageSize.width > 1, imageSize.height > 1 else { return 0 }
        let left = sideInset
        let right = imageSize.width - sideInset
        let yInset = verticalInset > 0 ? verticalInset : sideInset
        let top = yInset
        let bottom = imageSize.height - yInset
        var penalty: CGFloat = 0
        for rect in rects {
            if rect.minX < left { penalty += (left - rect.minX) * 40 }
            if rect.maxX > right { penalty += (rect.maxX - right) * 40 }
            if rect.minY < top { penalty += (top - rect.minY) * 20 }
            if rect.maxY > bottom { penalty += (rect.maxY - bottom) * 20 }
        }
        return penalty
    }

    static func drawMarker(
        label: String,
        routePoint: CGPoint,
        placesLabelOnLeadingSide: Bool,
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        drawCombinedMarker(
            distanceLabel: label,
            timeLabel: nil,
            routePoint: routePoint,
            placesLabelOnLeadingSide: placesLabelOnLeadingSide,
            contentScale: contentScale,
            in: cgContext
        )
    }

    /// Combined white capsule: both → `1km 16:50`; km-only / time-only → that part alone.
    static func drawMarker(
        distanceLabel: String?,
        timeLabel: String?,
        routePoint: CGPoint,
        placesLabelOnLeadingSide: Bool,
        verticalOffset: CGFloat = 0,
        contentScale: CGFloat,
        labelScale: CGFloat = RouteKilometerMarkerMetrics.markerLabelScale,
        in cgContext: CGContext
    ) {
        _ = labelScale
        drawCombinedMarker(
            distanceLabel: distanceLabel,
            timeLabel: timeLabel,
            routePoint: routePoint,
            placesLabelOnLeadingSide: placesLabelOnLeadingSide,
            verticalOffset: verticalOffset,
            contentScale: contentScale,
            in: cgContext
        )
    }

    /// Alias kept for share-summary call sites.
    static func drawShareSummaryMarker(
        distanceLabel: String?,
        timeLabel: String?,
        routePoint: CGPoint,
        placesLabelOnLeadingSide: Bool,
        verticalOffset: CGFloat = 0,
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        drawCombinedMarker(
            distanceLabel: distanceLabel,
            timeLabel: timeLabel,
            routePoint: routePoint,
            placesLabelOnLeadingSide: placesLabelOnLeadingSide,
            verticalOffset: verticalOffset,
            contentScale: contentScale,
            in: cgContext
        )
    }

    static func drawCombinedMarker(
        distanceLabel: String?,
        timeLabel: String?,
        routePoint: CGPoint,
        placesLabelOnLeadingSide: Bool,
        verticalOffset: CGFloat = 0,
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        let size = capsuleSize(
            distanceLabel: distanceLabel,
            timeLabel: timeLabel,
            contentScale: contentScale
        )
        let legacy = RouteKilometerLabelShift(
            placesLabelOnLeadingSide: placesLabelOnLeadingSide,
            verticalOffset: verticalOffset,
            capsuleWidth: size.width > 0 ? size.width : 72,
            contentScale: contentScale
        )
        drawCombinedMarker(
            distanceLabel: distanceLabel,
            timeLabel: timeLabel,
            routePoint: routePoint,
            centerOffset: legacy.centerOffset,
            contentScale: contentScale,
            in: cgContext
        )
    }

    static func drawCombinedMarker(
        distanceLabel: String?,
        timeLabel: String?,
        routePoint: CGPoint,
        centerOffset: CGPoint,
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        guard RouteKilometerMarkerMetrics.combinedLabel(distance: distanceLabel, time: timeLabel) != nil else {
            return
        }
        drawRouteDot(at: routePoint, contentScale: contentScale, in: cgContext)

        let fontSize = RouteKilometerMarkerMetrics.labelFontSize * contentScale
        let kmFont = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let timeFont = UIFont.systemFont(
            ofSize: fontSize,
            weight: RouteKilometerMarkerMetrics.timeLabelWeight(hasDistance: distanceLabel != nil)
        )
        let height = RouteKilometerMarkerMetrics.labelHeight * contentScale
        let padH = RouteKilometerMarkerMetrics.labelPadH * contentScale
        let innerGap = RouteKilometerMarkerMetrics.combinedInnerGap * contentScale

        let parts: [(String, UIFont, UIColor)]
        if let distanceLabel, let timeLabel {
            parts = [
                (distanceLabel, kmFont, RouteKilometerMarkerMetrics.inkUIColor),
                (timeLabel, timeFont, RouteKilometerMarkerMetrics.ink2UIColor)
            ]
        } else if let distanceLabel {
            parts = [(distanceLabel, kmFont, RouteKilometerMarkerMetrics.inkUIColor)]
        } else if let timeLabel {
            parts = [(timeLabel, timeFont, RouteKilometerMarkerMetrics.inkUIColor)]
        } else {
            return
        }

        var textWidth: CGFloat = 0
        for (index, part) in parts.enumerated() {
            if index > 0 { textWidth += innerGap }
            textWidth += (part.0 as NSString).size(withAttributes: [.font: part.1]).width
        }
        let capsuleWidth = textWidth + padH * 2
        let center = CGPoint(
            x: routePoint.x + centerOffset.x,
            y: routePoint.y + centerOffset.y
        )
        let capsuleRect = CGRect(
            x: center.x - capsuleWidth / 2,
            y: center.y - height / 2,
            width: capsuleWidth,
            height: height
        )
        let path = UIBezierPath(roundedRect: capsuleRect, cornerRadius: height / 2)

        cgContext.saveGState()
        // No capsule drop-shadow — share-summary AFTER must show white+green only.
        cgContext.setShadow(offset: .zero, blur: 0, color: nil)
        cgContext.setFillColor(UIColor.white.cgColor)
        cgContext.addPath(path.cgPath)
        cgContext.fillPath()
        cgContext.setStrokeColor(RouteKilometerMarkerMetrics.inkUIColor.withAlphaComponent(0.10).cgColor)
        cgContext.setLineWidth(max(0.5 * contentScale, 0.5))
        cgContext.addPath(path.cgPath)
        cgContext.strokePath()
        cgContext.restoreGState()

        var cursorX = capsuleRect.minX + padH
        let midY = capsuleRect.midY
        for (index, part) in parts.enumerated() {
            if index > 0 { cursorX += innerGap }
            let size = (part.0 as NSString).size(withAttributes: [.font: part.1])
            let origin = CGPoint(x: cursorX, y: midY - size.height / 2)
            (part.0 as NSString).draw(
                at: origin,
                withAttributes: [
                    .font: part.1,
                    .foregroundColor: part.2
                ]
            )
            cursorX += size.width
        }
    }

    /// 마커 전체 크기와 경로 점(원) 중심 — 3D 지도 주석 배치용.
    static func layoutMetrics(
        label: String,
        placesLabelOnLeadingSide: Bool,
        contentScale: CGFloat = 1
    ) -> (size: CGSize, routeDotCenter: CGPoint) {
        let capsule = capsuleSize(distanceLabel: label, timeLabel: nil, contentScale: contentScale)
        let dot = RouteKilometerMarkerMetrics.routeDotDiameter * contentScale
        let gap = RouteKilometerMarkerMetrics.labelGap * contentScale
        let pad = 6 * contentScale
        // gap is center→near-edge; span from far capsule edge to far dot edge ≈ capsule + gap + dot/2.
        let width = capsule.width + gap + dot / 2 + pad * 2
        let height = max(capsule.height, dot) + pad * 2

        let routeDotCenterX: CGFloat
        if placesLabelOnLeadingSide {
            routeDotCenterX = pad + capsule.width + gap
        } else {
            routeDotCenterX = pad + dot / 2
        }
        return (CGSize(width: width, height: height), CGPoint(x: routeDotCenterX, y: height / 2))
    }

    private static func labelCenter(
        capsuleWidth: CGFloat,
        routePoint: CGPoint,
        placesLabelOnLeadingSide: Bool,
        contentScale: CGFloat
    ) -> CGPoint {
        // labelGap = center → near edge (S7); not edge→edge.
        let gap = RouteKilometerMarkerMetrics.labelGap * contentScale
        let offsetX = gap + capsuleWidth / 2
        return CGPoint(
            x: routePoint.x + (placesLabelOnLeadingSide ? -offsetX : offsetX),
            y: routePoint.y
        )
    }

    private static func labelRects(
        distanceLabel: String?,
        timeLabel: String?,
        routePoint: CGPoint,
        placesLabelOnLeadingSide: Bool,
        verticalOffset: CGFloat,
        contentScale: CGFloat
    ) -> [CGRect] {
        let size = capsuleSize(distanceLabel: distanceLabel, timeLabel: timeLabel, contentScale: contentScale)
        guard size.width > 0 else { return [] }
        let center = labelCenter(
            capsuleWidth: size.width,
            routePoint: routePoint,
            placesLabelOnLeadingSide: placesLabelOnLeadingSide,
            contentScale: contentScale
        )
        return [
            CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2 + verticalOffset,
                width: size.width,
                height: size.height
            )
        ]
    }

    static func capsuleSize(
        distanceLabel: String?,
        timeLabel: String?,
        contentScale: CGFloat
    ) -> CGSize {
        guard RouteKilometerMarkerMetrics.combinedLabel(distance: distanceLabel, time: timeLabel) != nil else {
            return .zero
        }
        let fontSize = RouteKilometerMarkerMetrics.labelFontSize * contentScale
        let kmFont = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let timeFont = UIFont.systemFont(
            ofSize: fontSize,
            weight: RouteKilometerMarkerMetrics.timeLabelWeight(hasDistance: distanceLabel != nil)
        )
        let padH = RouteKilometerMarkerMetrics.labelPadH * contentScale
        let innerGap = RouteKilometerMarkerMetrics.combinedInnerGap * contentScale
        var textWidth: CGFloat = 0
        if let distanceLabel, let timeLabel {
            textWidth = (distanceLabel as NSString).size(withAttributes: [.font: kmFont]).width
                + innerGap
                + (timeLabel as NSString).size(withAttributes: [.font: timeFont]).width
        } else if let distanceLabel {
            textWidth = (distanceLabel as NSString).size(withAttributes: [.font: kmFont]).width
        } else if let timeLabel {
            textWidth = (timeLabel as NSString).size(withAttributes: [.font: timeFont]).width
        }
        return CGSize(
            width: textWidth + padH * 2,
            height: RouteKilometerMarkerMetrics.labelHeight * contentScale
        )
    }

    private static func endpointSeparation(
        of rects: [CGRect],
        from endpoints: [CGPoint],
        clearance: CGFloat
    ) -> CGFloat {
        guard !rects.isEmpty, !endpoints.isEmpty else { return .greatestFiniteMagnitude }
        var closest = CGFloat.greatestFiniteMagnitude
        for point in endpoints {
            for rect in rects {
                let expanded = rect.insetBy(dx: -clearance, dy: -clearance)
                if expanded.contains(point) {
                    let dx = max(rect.minX - point.x, point.x - rect.maxX, 0)
                    let dy = max(rect.minY - point.y, point.y - rect.maxY, 0)
                    closest = min(closest, hypot(dx, dy) - clearance)
                }
            }
        }
        return closest == .greatestFiniteMagnitude ? .greatestFiniteMagnitude : closest
    }

    private static func rectsOverlap(_ rects: [CGRect], _ obstacles: [CGRect], padding: CGFloat) -> Bool {
        for rect in rects {
            let expanded = rect.insetBy(dx: -padding, dy: -padding)
            for obstacle in obstacles where expanded.intersects(obstacle) {
                return true
            }
        }
        return false
    }

    private static func overlapArea(_ rects: [CGRect], _ obstacles: [CGRect]) -> CGFloat {
        var area: CGFloat = 0
        for rect in rects {
            for obstacle in obstacles {
                let hit = rect.intersection(obstacle)
                if !hit.isNull, hit.width > 0, hit.height > 0 {
                    area += hit.width * hit.height
                }
            }
        }
        return area
    }

    static func drawRouteDot(
        at center: CGPoint,
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        // Outer Ø10: white fill Ø10, stroke centered on Ø8 (border 2) → white Ø6 + ring (S6).
        let diameter = RouteKilometerMarkerMetrics.routeDotDiameter * contentScale
        let border = RouteKilometerMarkerMetrics.routeDotBorderWidth * contentScale
        let rect = CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        cgContext.saveGState()
        cgContext.setFillColor(UIColor.white.cgColor)
        cgContext.fillEllipse(in: rect)
        cgContext.setStrokeColor(RouteKilometerMarkerMetrics.accentUIColor.cgColor)
        cgContext.setLineWidth(border)
        cgContext.strokeEllipse(in: rect.insetBy(dx: border / 2, dy: border / 2))
        cgContext.restoreGState()
    }
}

#endif
