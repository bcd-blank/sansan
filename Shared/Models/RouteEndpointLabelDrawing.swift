//
//  RouteEndpointLabelDrawing.swift
//  Shared
//

#if os(iOS)

import UIKit

enum RouteEndpointLabelKind {
    case start
    case end

    var title: String {
        switch self {
        case .start: return "시작"
        case .end: return "종료"
        }
    }

    var systemImageName: String {
        switch self {
        case .start: return "play.circle.fill"
        case .end: return "flag.checkered"
        }
    }

    var dotColor: UIColor {
        switch self {
        case .start:
            return UIColor(red: 0.12, green: 0.72, blue: 0.45, alpha: 1)
        case .end:
            return UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        }
    }

    var capsuleColor: UIColor { dotColor }
}

enum RouteEndpointLabelDrawing {
    static func drawMarker(
        kind: RouteEndpointLabelKind,
        routePoint: CGPoint,
        placesLabelOnLeadingSide: Bool,
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        drawRouteDot(
            kind: kind,
            at: routePoint,
            contentScale: contentScale,
            in: cgContext
        )

        let labelCenter = labelCenterPoint(
            kind: kind,
            routePoint: routePoint,
            placesLabelOnLeadingSide: placesLabelOnLeadingSide,
            contentScale: contentScale
        )
        drawLabelCapsule(
            kind: kind,
            at: labelCenter,
            contentScale: contentScale,
            in: cgContext
        )
    }

    static func layoutMetrics(
        kind: RouteEndpointLabelKind,
        placesLabelOnLeadingSide: Bool,
        contentScale: CGFloat = 1
    ) -> (size: CGSize, routeDotCenter: CGPoint) {
        let capsule = capsuleSize(for: kind, contentScale: contentScale)
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

    static func previewImage(
        kind: RouteEndpointLabelKind,
        placesLabelOnLeadingSide: Bool = false,
        contentScale: CGFloat = 2
    ) -> UIImage {
        let metrics = layoutMetrics(
            kind: kind,
            placesLabelOnLeadingSide: placesLabelOnLeadingSide,
            contentScale: contentScale
        )
        let renderer = UIGraphicsImageRenderer(size: metrics.size)
        return renderer.image { context in
            drawMarker(
                kind: kind,
                routePoint: metrics.routeDotCenter,
                placesLabelOnLeadingSide: placesLabelOnLeadingSide,
                contentScale: contentScale,
                in: context.cgContext
            )
        }
    }

    private static func labelCenterPoint(
        kind: RouteEndpointLabelKind,
        routePoint: CGPoint,
        placesLabelOnLeadingSide: Bool,
        contentScale: CGFloat
    ) -> CGPoint {
        let capsuleWidth = capsuleSize(for: kind, contentScale: contentScale).width
        let gap = RouteKilometerMarkerMetrics.labelGap * contentScale
        let dotRadius = RouteKilometerMarkerMetrics.routeDotDiameter * contentScale / 2
        let offsetX = dotRadius + gap + capsuleWidth / 2

        return CGPoint(
            x: routePoint.x + (placesLabelOnLeadingSide ? -offsetX : offsetX),
            y: routePoint.y
        )
    }

    private static func capsuleSize(
        for kind: RouteEndpointLabelKind,
        contentScale: CGFloat
    ) -> CGSize {
        let iconSide = 11 * contentScale
        let gap = 4 * contentScale
        let font = UIFont.systemFont(ofSize: 10 * contentScale, weight: .bold)
        let textSize = (kind.title as NSString).size(withAttributes: [.font: font])
        let horizontalPadding = 7 * contentScale
        let verticalPadding = 3 * contentScale
        return CGSize(
            width: horizontalPadding * 2 + iconSide + gap + textSize.width,
            height: max(iconSide, textSize.height) + verticalPadding * 2
        )
    }

    private static func drawRouteDot(
        kind: RouteEndpointLabelKind,
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
        cgContext.setFillColor(kind.dotColor.cgColor)
        cgContext.fillEllipse(in: rect)
        cgContext.setStrokeColor(UIColor.white.cgColor)
        cgContext.setLineWidth(border)
        cgContext.strokeEllipse(in: rect.insetBy(dx: border / 2, dy: border / 2))
        cgContext.restoreGState()
    }

    private static func drawLabelCapsule(
        kind: RouteEndpointLabelKind,
        at center: CGPoint,
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        let font = UIFont.systemFont(ofSize: 10 * contentScale, weight: .bold)
        let capsuleSize = capsuleSize(for: kind, contentScale: contentScale)
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
        cgContext.setFillColor(kind.capsuleColor.cgColor)
        cgContext.addPath(capsulePath.cgPath)
        cgContext.fillPath()
        cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        cgContext.setLineWidth(1)
        cgContext.addPath(capsulePath.cgPath)
        cgContext.strokePath()
        cgContext.restoreGState()

        let iconSide = 11 * contentScale
        let gap = 4 * contentScale
        let iconRect = CGRect(
            x: capsuleRect.minX + 7 * contentScale,
            y: capsuleRect.midY - iconSide / 2,
            width: iconSide,
            height: iconSide
        )
        if let icon = UIImage(
            systemName: kind.systemImageName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: iconSide, weight: .semibold)
        )?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            icon.draw(in: iconRect)
        }

        let textOrigin = CGPoint(
            x: iconRect.maxX + gap,
            y: capsuleRect.midY - font.lineHeight / 2
        )
        (kind.title as NSString).draw(
            at: textOrigin,
            withAttributes: [
                .font: font,
                .foregroundColor: UIColor.white,
            ]
        )
    }
}

#endif
