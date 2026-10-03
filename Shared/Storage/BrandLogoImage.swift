//
//  BrandLogoImage.swift
//  Shared
//

#if os(iOS)

import UIKit

enum RouteBrandLogoMetrics {
    /// 레이아웃 기준 캔버스 너비(1080pt 경로 이미지).
    static let referenceCanvasWidth: CGFloat = 1080
    /// 1080pt 경로 이미지 기준 좌측 여백.
    static let leading: CGFloat = 32
    /// 1080pt 경로 이미지 기준 하단 여백.
    static let bottom: CGFloat = 42
    /// 1080pt 기준 로고 한 변.
    static let side: CGFloat = 156
    /// 인터랙티브 MapKit 좌하단 Apple 지도·법적 표기 위로 앱 로고를 올리기 위한 추가 하단 여백 (1080pt 기준).
    static let interactiveMapAttributionBottomOffset: CGFloat = 40

    static func layout(forCanvasWidth width: CGFloat) -> (leading: CGFloat, bottom: CGFloat, side: CGFloat) {
        let layoutScale = width / referenceCanvasWidth
        return (
            leading * layoutScale,
            bottom * layoutScale,
            side * layoutScale
        )
    }
}

enum BrandLogoImage {
    /// 지도·경로 이미지용 — 워드마크 없는 심볼만.
    private static let assetName = "SansanLogoSymbol"
    /// 어두운 지도·영상 오버레이용 흰색 심볼.
    private static let whiteAssetName = "SansanLogoSymbolWhite"

    /// PNG 합성·공유 렌더용 — SVG 에셋을 지정 크기로 래스터화합니다.
    static func rasterizedLogo(side: CGFloat) -> UIImage? {
        rasterizedLogo(named: assetName, side: side)
    }

    /// 3D 경로 영상 등 밝은 지도 위 흰색 심볼.
    static func rasterizedWhiteLogo(side: CGFloat) -> UIImage? {
        rasterizedLogo(named: whiteAssetName, side: side)
            ?? rasterizedLogo(side: side)
    }

    private static func rasterizedLogo(named assetName: String, side: CGFloat) -> UIImage? {
        guard side > 0, let source = UIImage(named: assetName, in: .main, compatibleWith: nil) else {
            return nil
        }

        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = max(source.scale, 2)

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

#endif
