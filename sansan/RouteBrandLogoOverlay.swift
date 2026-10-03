//
//  RouteBrandLogoOverlay.swift
//  sansan
//

#if os(iOS)

import SwiftUI

/// 경로 이미지 좌측 하단 브랜드 로고 (SVG 에셋, 저장 PNG와 동일 비율).
struct RouteBrandLogoOverlay: View {
    /// 1080pt 기준 좌측 여백 추가 (우측 이동).
    var leadingOffset: CGFloat = 0
    /// 1080pt 기준 하단 여백 추가 (상단 이동).
    var bottomOffset: CGFloat = 0
    /// 지정 시 `RouteBrandLogoMetrics.bottom` 대신 카드 하단 기준 여백(1080pt)으로 사용.
    var bottomInsetOverride: CGFloat?
    /// 로고 크기 배율 (1.0 = 기본).
    var sizeScale: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let layout = RouteBrandLogoMetrics.layout(forCanvasWidth: geometry.size.width)
            let layoutScale = geometry.size.width / RouteBrandLogoMetrics.referenceCanvasWidth
            let logoSide = layout.side * sizeScale

            Image("SansanLogoSymbol")
                .resizable()
                .scaledToFit()
                .frame(width: logoSide, height: logoSide)
                .shadow(
                    color: .black.opacity(0.18),
                    radius: 8 * layoutScale,
                    y: 2 * layoutScale
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, layout.leading + leadingOffset * layoutScale)
                .padding(
                    .bottom,
                    (bottomInsetOverride ?? layout.bottom) + bottomOffset * layoutScale
                )
        }
        .allowsHitTesting(false)
    }
}

#endif
