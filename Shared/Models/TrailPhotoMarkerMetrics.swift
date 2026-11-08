//
//  TrailPhotoMarkerMetrics.swift
//  Shared
//

import CoreGraphics
import Foundation

enum TrailPhotoMarkerMetrics {
    static let scale: CGFloat = 0.7

    static let outerDiameter: CGFloat = 32 * scale
    static let innerDiameter: CGFloat = 24 * scale
    static let iconPointSize: CGFloat = 12 * scale
    static let tipHeight: CGFloat = 6 * scale
    static let tipWidth: CGFloat = 10 * scale
    static let clusterRadius: CGFloat = 22 * scale

    static var totalHeight: CGFloat { outerDiameter + tipHeight }
    static var totalWidth: CGFloat { outerDiameter }

    /// 같은 GPS(약 2m 이내) 사진을 한 포인트 클러스터로 묶습니다.
    static let sameLocationThresholdMeters: Double = 2
}

#if os(iOS)
import UIKit

enum TrailPhotoMarkerDrawing {
    private static let pinBlue = UIColor(red: 0, green: 0.48, blue: 1, alpha: 1)
    /// `tip` — 마커 뾰족한 끝이 가리키는 지도 좌표(스냅샷 화면 점).
    static func drawPin(
        tip: CGPoint,
        rotationDegrees: CGFloat,
        in cgContext: CGContext,
        contentScale: CGFloat = 1
    ) {
        let scale = TrailPhotoMarkerMetrics.scale * contentScale
        let outer = TrailPhotoMarkerMetrics.outerDiameter * contentScale
        let inner = TrailPhotoMarkerMetrics.innerDiameter * contentScale
        let tipH = TrailPhotoMarkerMetrics.tipHeight * contentScale
        let tipW = TrailPhotoMarkerMetrics.tipWidth * contentScale
        let iconSize = TrailPhotoMarkerMetrics.iconPointSize * contentScale

        cgContext.saveGState()
        cgContext.translateBy(x: tip.x, y: tip.y)
        cgContext.rotate(by: rotationDegrees * .pi / 180)

        let bodyCenterY = -(outer / 2 + tipH)
        let outerRect = CGRect(
            x: -outer / 2,
            y: bodyCenterY - outer / 2,
            width: outer,
            height: outer
        )
        let innerRect = CGRect(
            x: -inner / 2,
            y: bodyCenterY - inner / 2,
            width: inner,
            height: inner
        )

        let tipPath = UIBezierPath()
        tipPath.move(to: CGPoint(x: 0, y: 0))
        tipPath.addLine(to: CGPoint(x: -tipW / 2, y: -tipH))
        tipPath.addLine(to: CGPoint(x: tipW / 2, y: -tipH))
        tipPath.close()

        cgContext.setShadow(
            offset: CGSize(width: 0, height: 2 * scale),
            blur: 4 * scale,
            color: UIColor.black.withAlphaComponent(0.15).cgColor
        )
        cgContext.setFillColor(UIColor.white.cgColor)
        cgContext.fillEllipse(in: outerRect)
        cgContext.setFillColor(pinBlue.cgColor)
        cgContext.fillEllipse(in: innerRect)
        cgContext.setFillColor(pinBlue.cgColor)
        cgContext.addPath(tipPath.cgPath)
        cgContext.fillPath()

        cgContext.restoreGState()

        cgContext.saveGState()
        cgContext.translateBy(x: tip.x, y: tip.y)
        cgContext.rotate(by: rotationDegrees * .pi / 180)

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .bold)
        if let symbol = UIImage(systemName: "camera.fill", withConfiguration: symbolConfig) {
            let symbolSize = symbol.size
            let symbolRect = CGRect(
                x: -symbolSize.width / 2,
                y: bodyCenterY - symbolSize.height / 2,
                width: symbolSize.width,
                height: symbolSize.height
            )
            symbol.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: symbolRect)
        }
        cgContext.restoreGState()
    }
}
#endif
