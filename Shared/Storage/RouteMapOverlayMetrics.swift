//
//  RouteMapOverlayMetrics.swift
//  Shared
//

#if os(iOS)

import CoreGraphics
import UIKit

/// 경로 이미지 카드 위 고정 레이어(Apple 법적 표기·브랜드 로고) 배치 기준 — 1080pt 캔버스.
enum RouteMapOverlayMetrics {
    static let referenceCanvasWidth: CGFloat = 1080

    /// Apple Maps 법적 표기 스트립 높이.
    static let legalAttributionHeight: CGFloat = 34
    /// Apple Maps 법적 표기 스트립 너비(로고+문구).
    static let legalAttributionWidth: CGFloat = 148
    /// 법적 표기 좌측 여백.
    static let legalAttributionLeading: CGFloat = 6
    /// 브랜드 로고가 법적 표기 위에 올라갈 때 추가 하단 여백.
    static let brandLogoAboveAttributionGap: CGFloat = 6
    /// 사진 저장 등 법적 표기 레이어 없을 때 — 로고 하단 여백(1080pt). 표기는 PNG 후처리로 제거.
    static let brandLogoCoveringAttributionBottomInset: CGFloat = 6

    static func scaled(
        _ value: CGFloat,
        forCanvasWidth width: CGFloat
    ) -> CGFloat {
        guard referenceCanvasWidth > 0 else { return value }
        return value * (width / referenceCanvasWidth)
    }

    static func legalAttributionStripHeight(forCanvasWidth width: CGFloat) -> CGFloat {
        scaled(legalAttributionHeight, forCanvasWidth: width)
    }

    /// MKMapView 네이티브 좌하단 표기 — 상세 지도와 동일하게 최소 40pt를 잘라냅니다.
    static func mkMapCaptureAttributionStripHeight(forMapViewWidth width: CGFloat) -> CGFloat {
        max(
            legalAttributionStripHeight(forCanvasWidth: width),
            RouteBrandLogoMetrics.interactiveMapAttributionBottomOffset
        )
    }

    /// 표기 스트립을 제외한 저장·합성용 캔버스(종횡비 유지).
    static func mapExportCanvasSize(fromFullMapSize full: CGSize) -> CGSize {
        let strip = mkMapCaptureAttributionStripHeight(forMapViewWidth: full.width)
        return CGSize(width: full.width, height: max(full.height - strip, 1))
    }

    /// 스냅샷·캡처 시 region fit에 쓰는 전체 지도 프레임.
    static func fullMapCanvasSize(matchingExport export: CGSize) -> CGSize {
        let strip = mkMapCaptureAttributionStripHeight(forMapViewWidth: export.width)
        return CGSize(width: export.width, height: export.height + strip)
    }

    /// 하단 표기 스트립을 잘라 지도만 남깁니다(흰색 채움 없음).
    static func imageByCroppingAttributionStrip(
        from image: UIImage,
        stripHeight: CGFloat
    ) -> UIImage {
        guard stripHeight > 0, stripHeight < image.size.height else { return image }

        let cropHeight = image.size.height - stripHeight
        let pixelRect = CGRect(
            x: 0,
            y: 0,
            width: image.size.width * image.scale,
            height: cropHeight * image.scale
        ).integral

        guard let source = image.cgImage,
              let cropped = source.cropping(to: pixelRect)
        else { return image }

        return UIImage(
            cgImage: cropped,
            scale: image.scale,
            orientation: image.imageOrientation
        )
    }

    static func brandLogoBottomOffset(forCanvasWidth width: CGFloat) -> CGFloat {
        legalAttributionStripHeight(forCanvasWidth: width)
            + scaled(brandLogoAboveAttributionGap, forCanvasWidth: width)
    }

    /// MKMapView가 그리는 좌하단 「지도·법적 정보」 영역(저장용 이미지에서 덮을 때).
    static func nativeAttributionMaskRect(forCanvasSize size: CGSize) -> CGRect {
        let stripHeight = mkMapCaptureAttributionStripHeight(forMapViewWidth: size.width)
        let badgeWidth = scaled(legalAttributionWidth, forCanvasWidth: size.width)
        let leading = scaled(legalAttributionLeading, forCanvasWidth: size.width)
        let padding = scaled(10, forCanvasWidth: size.width)
        return CGRect(
            x: 0,
            y: size.height - stripHeight - padding,
            width: min(size.width * 0.55, badgeWidth + leading + padding * 3),
            height: stripHeight + padding * 2
        )
    }

    /// 사진 저장 등 정적 이미지 — 네이티브 Apple Maps 법적 표기를 지도 위에서 가립니다.
    static func maskingNativeAppleMapsAttribution(on image: UIImage) -> UIImage {
        let size = image.size
        let maskRect = nativeAttributionMaskRect(forCanvasSize: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(maskRect)
        }
    }

    /// 사진 저장 카드 — 좌하단 Apple Maps 표기를 지도 색으로 덮습니다(흰색 패치 회피).
    static func coveringNativeAppleMapsAttribution(on image: UIImage) -> UIImage {
        let size = image.size
        let maskRect = nativeAttributionMaskRect(forCanvasSize: size)
        guard maskRect.width > 1, maskRect.height > 1,
              maskRect.minY > 2,
              let source = image.cgImage else {
            return image
        }

        let sampleHeight = min(max(6, maskRect.height * 0.18), maskRect.minY)
        let sampleRect = CGRect(
            x: maskRect.minX,
            y: maskRect.minY - sampleHeight,
            width: maskRect.width,
            height: sampleHeight
        )
        let pixelSample = CGRect(
            x: sampleRect.origin.x * image.scale,
            y: sampleRect.origin.y * image.scale,
            width: sampleRect.width * image.scale,
            height: sampleRect.height * image.scale
        ).integral

        guard let sampleCrop = source.cropping(to: pixelSample) else {
            return maskingNativeAppleMapsAttribution(on: image)
        }

        let sampleImage = UIImage(
            cgImage: sampleCrop,
            scale: image.scale,
            orientation: image.imageOrientation
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
            sampleImage.draw(in: maskRect)
        }
    }
}

#endif
