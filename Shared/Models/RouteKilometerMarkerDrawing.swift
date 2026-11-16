//
//  RouteKilometerMarkerDrawing.swift
//  Shared
//
//  Combined white km/time capsules shared by detail map, share summary,
//  card export overlays, and flythrough.
//

#if os(iOS)

import UIKit

struct RouteKilometerLabelShift: Equatable {
    var placesLabelOnLeadingSide: Bool
    var verticalOffset: CGFloat
}

struct RouteKilometerLabelRequest {
    let kilometer: Int
    let distanceLabel: String?
    let timeLabel: String?
    let routePoint: CGPoint
    let preferredLeadingSide: Bool
}

enum RouteKilometerMarkerDrawing {
    /// 시작·종료 점(지름 18) 밖으로 라벨을 띄우는 여유.
    private static let endpointClearanceRadius: CGFloat = 18 / 2 + 6

    /// 겹치는 라벨을 포인트 옆에서만 조금 떼어 놓습니다.
    /// When `imageSize` is set, capsules must stay inside the canvas (impl4 #2 / Android `imageBoundsPenalty`).
    static func labelShifts(
        for markers: [RouteKilometerLabelRequest],
        endpointPoints: [CGPoint],
        contentScale: CGFloat,
        imageSize: CGSize = .zero,
        sideInset: CGFloat = 0
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
                sideInset: sideInset
            )
            shifts[marker.kilometer] = placed.shift
            occupied.append(contentsOf: placed.rects)
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
        sideInset: CGFloat
    ) -> (shift: RouteKilometerLabelShift, rects: [CGRect]) {
        let clearance = endpointClearanceRadius * contentScale
        let labelPadding = 3 * contentScale
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
            let boundsHit = imageBoundsPenalty(rects, imageSize: imageSize, sideInset: sideInset)
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
                    return (bestShift, bestRects)
                }
            }
        }
        if foundInBounds {
            return (bestShift, bestRects)
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
            return (
                RouteKilometerLabelShift(placesLabelOnLeadingSide: fallbackSide, verticalOffset: 0),
                fallbackRects
            )
        }
        return (bestShift, bestRects)
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

    /// Heavy penalty when capsule leaves the side-inset band `[sideInset, width−sideInset]`.
    private static func imageBoundsPenalty(
        _ rects: [CGRect],
        imageSize: CGSize,
        sideInset: CGFloat
    ) -> CGFloat {
        guard imageSize.width > 1, imageSize.height > 1 else { return 0 }
        let left = sideInset
        let right = imageSize.width - sideInset
        let top = sideInset
        let bottom = imageSize.height - sideInset
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
        let center = labelCenter(
            capsuleWidth: capsuleWidth,
            routePoint: routePoint,
            placesLabelOnLeadingSide: placesLabelOnLeadingSide,
            contentScale: contentScale
        )
        let capsuleRect = CGRect(
            x: center.x - capsuleWidth / 2,
            y: center.y - height / 2 + verticalOffset,
            width: capsuleWidth,
            height: height
        )
        let path = UIBezierPath(roundedRect: capsuleRect, cornerRadius: height / 2)

        cgContext.saveGState()
        cgContext.setShadow(
            offset: CGSize(width: 0, height: 2 * contentScale),
            blur: 6 * contentScale,
            color: RouteKilometerMarkerMetrics.inkUIColor.withAlphaComponent(0.10).cgColor
        )
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

    private static func drawRouteDot(
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
