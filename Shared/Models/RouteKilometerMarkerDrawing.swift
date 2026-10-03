//
//  RouteKilometerMarkerDrawing.swift
//  Shared
//

#if os(iOS)

import UIKit

enum RouteKilometerMarkerDrawing {
    private static let routeGreen = UIColor(red: 0.12, green: 0.72, blue: 0.45, alpha: 1)

    static func drawMarker(
        label: String,
        routePoint: CGPoint,
        placesLabelOnLeadingSide: Bool,
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        drawRouteDot(
            at: routePoint,
            contentScale: contentScale,
            in: cgContext
        )

        let labelCenter = labelCenterPoint(
            label: label,
            routePoint: routePoint,
            placesLabelOnLeadingSide: placesLabelOnLeadingSide,
            contentScale: contentScale
        )
        drawLabelCapsule(
            label: label,
            at: labelCenter,
            contentScale: contentScale,
            in: cgContext
        )
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
        contentScale: CGFloat
    ) -> CGPoint {
        let capsuleWidth = capsuleSize(for: label, contentScale: contentScale).width
        let gap = RouteKilometerMarkerMetrics.labelGap * contentScale
        let dotRadius = RouteKilometerMarkerMetrics.routeDotDiameter * contentScale / 2
        let offsetX = dotRadius + gap + capsuleWidth / 2

        return CGPoint(
            x: routePoint.x + (placesLabelOnLeadingSide ? -offsetX : offsetX),
            y: routePoint.y
        )
    }

    private static func capsuleSize(for label: String, contentScale: CGFloat) -> CGSize {
        let font = UIFont.systemFont(ofSize: 10 * contentScale, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (label as NSString).size(withAttributes: attributes)
        let horizontalPadding = 6 * contentScale
        let verticalPadding = 3 * contentScale
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
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        let font = UIFont.systemFont(ofSize: 10 * contentScale, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
        ]
        let capsuleSize = capsuleSize(for: label, contentScale: contentScale)
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
        cgContext.setFillColor(routeGreen.cgColor)
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
