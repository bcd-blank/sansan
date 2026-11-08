//
//  FlythroughEndpointLabelPreview.swift
//  sansan
//
//  시작·종료 지점 라벨 예시 이미지 생성(지도 렌더 없이 합성).
//

#if os(iOS)

import UIKit

enum FlythroughEndpointLabelPreview {
    static let canvasSize = CGSize(width: 360, height: 640)

    static func startFrameImage() -> UIImage {
        compositeFrame(
            kind: .start,
            labelPoint: CGPoint(x: 132, y: 286),
            placesLabelOnLeadingSide: false
        )
    }

    static func endFrameImage() -> UIImage {
        compositeFrame(
            kind: .end,
            labelPoint: CGPoint(x: 228, y: 248),
            placesLabelOnLeadingSide: true
        )
    }

    private static func compositeFrame(
        kind: RouteEndpointLabelKind,
        labelPoint: CGPoint,
        placesLabelOnLeadingSide: Bool
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            let cg = context.cgContext
            drawMapBackdrop(in: cg)
            drawSampleRoute(in: cg, kind: kind)
            drawTitleBar(in: cg, kind: kind)

            let labelMetrics = RouteEndpointLabelDrawing.layoutMetrics(
                kind: kind,
                placesLabelOnLeadingSide: placesLabelOnLeadingSide,
                contentScale: 1.15
            )
            let origin = CGPoint(
                x: labelPoint.x - labelMetrics.routeDotCenter.x,
                y: labelPoint.y - labelMetrics.routeDotCenter.y
            )
            cg.saveGState()
            cg.translateBy(x: origin.x, y: origin.y)
            RouteEndpointLabelDrawing.drawMarker(
                kind: kind,
                routePoint: labelMetrics.routeDotCenter,
                placesLabelOnLeadingSide: placesLabelOnLeadingSide,
                contentScale: 1.15,
                in: cg
            )
            cg.restoreGState()
        }
    }

    private static func drawMapBackdrop(in cg: CGContext) {
        let colors = [
            UIColor(red: 0.20, green: 0.34, blue: 0.22, alpha: 1).cgColor,
            UIColor(red: 0.28, green: 0.42, blue: 0.27, alpha: 1).cgColor,
            UIColor(red: 0.34, green: 0.48, blue: 0.31, alpha: 1).cgColor,
        ] as CFArray
        let space = CGColorSpaceCreateDeviceRGB()
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.55, 1]) {
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: canvasSize.width, y: canvasSize.height),
                options: []
            )
        }
    }

    private static func drawSampleRoute(in cg: CGContext, kind: RouteEndpointLabelKind) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 118, y: 292))
        path.addCurve(
            to: CGPoint(x: 242, y: 252),
            controlPoint1: CGPoint(x: 156, y: 318),
            controlPoint2: CGPoint(x: 198, y: 228)
        )
        cg.saveGState()
        cg.setStrokeColor(UIColor(red: 0.16, green: 0.86, blue: 0.38, alpha: 1).cgColor)
        cg.setLineWidth(kind == .end ? 2.2 : 2.8)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        cg.addPath(path.cgPath)
        cg.strokePath()
        cg.restoreGState()
    }

    private static func drawTitleBar(in cg: CGContext, kind: RouteEndpointLabelKind) {
        let title = kind == .start ? "백운산" : "백운산"
        let phase = kind == .start ? "영상 시작" : "영상 종료"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        let phaseAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.72),
        ]
        (title as NSString).draw(at: CGPoint(x: 24, y: 54), withAttributes: attrs)
        (phase as NSString).draw(at: CGPoint(x: 24, y: 82), withAttributes: phaseAttrs)

        if kind == .end {
            let graphRect = CGRect(x: 24, y: canvasSize.height - 168, width: canvasSize.width - 48, height: 72)
            cg.setFillColor(UIColor.black.withAlphaComponent(0.28).cgColor)
            cg.fill(graphRect)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.18).cgColor)
            cg.setLineWidth(1)
            cg.stroke(graphRect)
        }
    }

    @discardableResult
    static func writePreviewImages(to directory: URL) -> (start: URL, end: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let startURL = directory.appendingPathComponent("flythrough-start-endpoint-label.png")
        let endURL = directory.appendingPathComponent("flythrough-end-endpoint-label.png")
        if let data = startFrameImage().pngData() {
            try? data.write(to: startURL)
        }
        if let data = endFrameImage().pngData() {
            try? data.write(to: endURL)
        }
        return (startURL, endURL)
    }
}

#endif
