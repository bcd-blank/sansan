//
//  RouteKilometerMarkerDrawing.swift
//  Shared
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
    private static let routeGreen = UIColor(red: 0.12, green: 0.72, blue: 0.45, alpha: 1)
    private static let timeBlue = UIColor(red: 0, green: 122.0 / 255.0, blue: 1, alpha: 1)
    /// 시작·종료 점(지름 17) 밖으로 라벨을 띄우는 여유.
    private static let endpointClearanceRadius: CGFloat = 17 / 2 + 6

    /// 겹치는 거리·시간 라벨을 포인트 옆에서만 조금 떼어 놓습니다.
    /// 반대편, 또는 캡슐 하나 안쪽의 위아래만 허용합니다.
    static func labelShifts(
        for markers: [RouteKilometerLabelRequest],
        endpointPoints: [CGPoint],
        contentScale: CGFloat
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
                contentScale: contentScale
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
        contentScale: CGFloat
    ) -> (shift: RouteKilometerLabelShift, rects: [CGRect]) {
        let clearance = endpointClearanceRadius * contentScale
        let labelPadding = 3 * contentScale
        let anchorLabel = distanceLabel ?? timeLabel ?? ""
        let anchorScale = RouteKilometerMarkerMetrics.markerLabelScale
        let anchorHeight = capsuleSize(
            for: anchorLabel,
            contentScale: contentScale,
            labelScale: anchorScale
        ).height
        let unit = max(anchorHeight, 12 * contentScale)
        let nudges: [(sideIsPreferred: Bool, multiplier: CGFloat)] = [
            (true, 0),
            (false, 0),
            (true, -1),
            (true, 1),
            (false, -1),
            (false, 1),
            (true, -1.6),
            (true, 1.6),
            (false, -1.6),
            (false, 1.6)
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

        for nudge in nudges {
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
            let endpointScore = endpointSeparation(of: rects, from: endpointPoints, clearance: clearance)
            let overlapsLabels = rectsOverlap(rects, occupied, padding: labelPadding)
            if endpointScore == .greatestFiniteMagnitude, !overlapsLabels {
                return (
                    RouteKilometerLabelShift(
                        placesLabelOnLeadingSide: side,
                        verticalOffset: verticalOffset
                    ),
                    rects
                )
            }
            let endpointPenalty: CGFloat = endpointScore == .greatestFiniteMagnitude ? 0 : -endpointScore * 48
            let penalty = overlapArea(rects, occupied)
                + endpointPenalty
                + abs(nudge.multiplier) * 6
                + (nudge.sideIsPreferred ? 0 : 3)
            if penalty < bestPenalty {
                bestPenalty = penalty
                bestShift = RouteKilometerLabelShift(
                    placesLabelOnLeadingSide: side,
                    verticalOffset: verticalOffset
                )
                bestRects = rects
            }
        }
        return (bestShift, bestRects)
    }

    static func drawMarker(
        label: String,
        routePoint: CGPoint,
        placesLabelOnLeadingSide: Bool,
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        drawMarker(
            distanceLabel: label,
            timeLabel: nil,
            routePoint: routePoint,
            placesLabelOnLeadingSide: placesLabelOnLeadingSide,
            contentScale: contentScale,
            labelScale: 1,
            in: cgContext
        )
    }

    /// 거리 라벨 옆에 두고, 시간 라벨은 그 위에 간격을 두고 그립니다.
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
        guard distanceLabel != nil || timeLabel != nil else { return }
        drawRouteDot(
            at: routePoint,
            contentScale: contentScale,
            in: cgContext
        )

        let anchorLabel = distanceLabel ?? timeLabel ?? ""
        let anchorCenter = labelCenterPoint(
            label: anchorLabel,
            routePoint: routePoint,
            placesLabelOnLeadingSide: placesLabelOnLeadingSide,
            contentScale: contentScale,
            labelScale: labelScale
        )
        let shiftedAnchor = CGPoint(x: anchorCenter.x, y: anchorCenter.y + verticalOffset)
        if let distanceLabel {
            drawLabelCapsule(
                label: distanceLabel,
                at: shiftedAnchor,
                fill: routeGreen,
                contentScale: contentScale,
                labelScale: labelScale,
                in: cgContext
            )
        }
        if let timeLabel {
            let timeSize = capsuleSize(for: timeLabel, contentScale: contentScale, labelScale: labelScale)
            let timeCenter: CGPoint
            if let distanceLabel {
                let distanceHeight = capsuleSize(
                    for: distanceLabel,
                    contentScale: contentScale,
                    labelScale: labelScale
                ).height
                let stackGap = 3 * contentScale
                timeCenter = CGPoint(
                    x: shiftedAnchor.x,
                    y: shiftedAnchor.y - distanceHeight / 2 - stackGap - timeSize.height / 2
                )
            } else {
                timeCenter = shiftedAnchor
            }
            drawLabelCapsule(
                label: timeLabel,
                at: timeCenter,
                fill: timeBlue,
                contentScale: contentScale,
                labelScale: labelScale,
                in: cgContext
            )
        }
    }

    /// 마커 전체 크기와 경로 점(원) 중심 — 3D 지도 주석 배치용.
    static func layoutMetrics(
        label: String,
        placesLabelOnLeadingSide: Bool,
        contentScale: CGFloat = 1
    ) -> (size: CGSize, routeDotCenter: CGPoint) {
        let capsule = capsuleSize(for: label, contentScale: contentScale)
        let dot = RouteKilometerMarkerMetrics.routeDotDiameter * contentScale
        let gap = RouteKilometerMarkerMetrics.labelGap * contentScale
        let pad = 6 * contentScale

        let width = capsule.width + gap + dot + pad * 2
        let height = max(capsule.height, dot) + pad * 2

        let routeDotCenterX: CGFloat
        if placesLabelOnLeadingSide {
            routeDotCenterX = pad + capsule.width + gap + dot / 2
        } else {
            routeDotCenterX = pad + dot / 2
        }
        return (CGSize(width: width, height: height), CGPoint(x: routeDotCenterX, y: height / 2))
    }

    private static func labelCenterPoint(
        label: String,
        routePoint: CGPoint,
        placesLabelOnLeadingSide: Bool,
        contentScale: CGFloat,
        labelScale: CGFloat = 1
    ) -> CGPoint {
        let capsuleWidth = capsuleSize(for: label, contentScale: contentScale, labelScale: labelScale).width
        let gap = RouteKilometerMarkerMetrics.labelGap * contentScale
        let dotRadius = RouteKilometerMarkerMetrics.routeDotDiameter * contentScale / 2
        let offsetX = dotRadius + gap + capsuleWidth / 2

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
        let anchorLabel = distanceLabel ?? timeLabel ?? ""
        guard !anchorLabel.isEmpty else { return [] }
        let labelScale = RouteKilometerMarkerMetrics.markerLabelScale
        let anchorCenter = labelCenterPoint(
            label: anchorLabel,
            routePoint: routePoint,
            placesLabelOnLeadingSide: placesLabelOnLeadingSide,
            contentScale: contentScale,
            labelScale: labelScale
        )
        let shiftedAnchor = CGPoint(x: anchorCenter.x, y: anchorCenter.y + verticalOffset)
        var rects: [CGRect] = []
        if let distanceLabel {
            rects.append(
                rect(
                    for: distanceLabel,
                    center: shiftedAnchor,
                    contentScale: contentScale,
                    labelScale: labelScale
                )
            )
            if let timeLabel {
                let distanceHeight = capsuleSize(
                    for: distanceLabel,
                    contentScale: contentScale,
                    labelScale: labelScale
                ).height
                let timeSize = capsuleSize(for: timeLabel, contentScale: contentScale, labelScale: labelScale)
                let stackGap = 3 * contentScale
                let timeCenter = CGPoint(
                    x: shiftedAnchor.x,
                    y: shiftedAnchor.y - distanceHeight / 2 - stackGap - timeSize.height / 2
                )
                rects.append(rect(for: timeLabel, center: timeCenter, contentScale: contentScale, labelScale: labelScale))
            }
        } else if let timeLabel {
            rects.append(rect(for: timeLabel, center: shiftedAnchor, contentScale: contentScale, labelScale: labelScale))
        }
        return rects
    }

    private static func rect(
        for label: String,
        center: CGPoint,
        contentScale: CGFloat,
        labelScale: CGFloat = 1
    ) -> CGRect {
        let size = capsuleSize(for: label, contentScale: contentScale, labelScale: labelScale)
        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// 겹치면 음수(깊을수록 작음), 모두 비키면 무한대.
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

    private static func capsuleSize(
        for label: String,
        contentScale: CGFloat,
        labelScale: CGFloat = 1
    ) -> CGSize {
        let font = UIFont.systemFont(ofSize: 10 * contentScale * labelScale, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (label as NSString).size(withAttributes: attributes)
        let horizontalPadding = 6 * contentScale * labelScale
        let verticalPadding = 3 * contentScale * labelScale
        return CGSize(
            width: textSize.width + horizontalPadding * 2,
            height: textSize.height + verticalPadding * 2
        )
    }

    private static func drawRouteDot(
        at center: CGPoint,
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        let diameter = RouteKilometerMarkerMetrics.routeDotDiameter * contentScale
        let border = RouteKilometerMarkerMetrics.routeDotBorderWidth * contentScale
        let rect = CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )

        cgContext.saveGState()
        cgContext.setShadow(
            offset: CGSize(width: 0, height: 1 * contentScale),
            blur: 1.5 * contentScale,
            color: UIColor.black.withAlphaComponent(0.18).cgColor
        )
        cgContext.setFillColor(routeGreen.cgColor)
        cgContext.fillEllipse(in: rect)
        cgContext.setStrokeColor(UIColor.white.cgColor)
        cgContext.setLineWidth(border)
        cgContext.strokeEllipse(in: rect.insetBy(dx: border / 2, dy: border / 2))
        cgContext.restoreGState()
    }

    private static func drawLabelCapsule(
        label: String,
        at center: CGPoint,
        fill: UIColor,
        contentScale: CGFloat,
        labelScale: CGFloat = 1,
        in cgContext: CGContext
    ) {
        let font = UIFont.systemFont(ofSize: 10 * contentScale * labelScale, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
        ]
        let capsuleSize = capsuleSize(for: label, contentScale: contentScale, labelScale: labelScale)
        let capsuleRect = CGRect(
            x: center.x - capsuleSize.width / 2,
            y: center.y - capsuleSize.height / 2,
            width: capsuleSize.width,
            height: capsuleSize.height
        )
        let capsulePath = UIBezierPath(
            roundedRect: capsuleRect,
            cornerRadius: capsuleSize.height / 2
        )

        cgContext.saveGState()
        cgContext.setShadow(
            offset: CGSize(width: 0, height: 1 * contentScale),
            blur: 2 * contentScale,
            color: UIColor.black.withAlphaComponent(0.2).cgColor
        )
        cgContext.setFillColor(fill.cgColor)
        cgContext.addPath(capsulePath.cgPath)
        cgContext.fillPath()
        cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        cgContext.setLineWidth(1)
        cgContext.addPath(capsulePath.cgPath)
        cgContext.strokePath()
        cgContext.restoreGState()

        let textSize = (label as NSString).size(withAttributes: attributes)
        let textOrigin = CGPoint(
            x: capsuleRect.midX - textSize.width / 2,
            y: capsuleRect.midY - textSize.height / 2
        )
        (label as NSString).draw(at: textOrigin, withAttributes: attributes)
    }
}

#endif
