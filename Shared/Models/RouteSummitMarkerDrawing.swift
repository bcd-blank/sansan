//
//  RouteSummitMarkerDrawing.swift
//  Shared
//
//  기록 상세 지도의 산 이름 마커를 저장·공유 PNG에 동일하게 그립니다.
//

#if os(iOS)

import UIKit

enum RouteSummitMarkerDrawing {
    private static let iconColor = UIColor(red: 0.45, green: 0.34, blue: 0.24, alpha: 1)

    static func drawMarker(
        name: String,
        at point: CGPoint,
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        let iconSize = 11 * contentScale
        let spacing = 2 * contentScale
        let capsule = capsuleSize(for: name, contentScale: contentScale)
        let iconCenter = CGPoint(x: point.x, y: point.y - iconSize / 2)
        let capsuleCenter = CGPoint(
            x: point.x,
            y: iconCenter.y - iconSize / 2 - spacing - capsule.height / 2
        )

        drawIcon(at: iconCenter, size: iconSize, contentScale: contentScale, in: cgContext)
        drawLabelCapsule(name: name, at: capsuleCenter, contentScale: contentScale, in: cgContext)
    }

    private static func drawIcon(
        at center: CGPoint,
        size: CGFloat,
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        let configuration = UIImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        guard let icon = UIImage(systemName: "mountain.2.fill", withConfiguration: configuration)?
            .withTintColor(iconColor, renderingMode: .alwaysOriginal)
        else {
            return
        }

        let rect = CGRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size,
            height: size
        )
        cgContext.saveGState()
        cgContext.setShadow(
            offset: .zero,
            blur: 1 * contentScale,
            color: UIColor.white.withAlphaComponent(0.85).cgColor
        )
        icon.draw(in: rect)
        cgContext.restoreGState()
    }

    private static func capsuleSize(for name: String, contentScale: CGFloat) -> CGSize {
        let font = UIFont.systemFont(ofSize: 9 * contentScale, weight: .semibold)
        let textSize = (name as NSString).size(withAttributes: [.font: font])
        return CGSize(
            width: textSize.width + 10 * contentScale,
            height: textSize.height + 4 * contentScale
        )
    }

    private static func drawLabelCapsule(
        name: String,
        at center: CGPoint,
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        let font = UIFont.systemFont(ofSize: 9 * contentScale, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label,
        ]
        let size = capsuleSize(for: name, contentScale: contentScale)
        let rect = CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        let path = UIBezierPath(roundedRect: rect, cornerRadius: size.height / 2)

        cgContext.saveGState()
        cgContext.setFillColor(UIColor.systemBackground.withAlphaComponent(0.88).cgColor)
        cgContext.setShadow(
            offset: CGSize(width: 0, height: 0.5 * contentScale),
            blur: 1.5 * contentScale,
            color: UIColor.black.withAlphaComponent(0.16).cgColor
        )
        cgContext.addPath(path.cgPath)
        cgContext.fillPath()
        cgContext.restoreGState()

        let textSize = (name as NSString).size(withAttributes: attributes)
        (name as NSString).draw(
            at: CGPoint(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2
            ),
            withAttributes: attributes
        )
    }
}

#endif
