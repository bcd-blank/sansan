//
//  RouteMapImageCardChrome.swift
//  sansan
//
//  경로 비트맵 + 고정 법적 표기·브랜드 로고 레이어.
//

#if os(iOS)

import SwiftUI

struct RouteMapImageCardChrome<Content: View>: View {
    var showsBrandLogo: Bool
    /// 사진 앨범 저장 등 정적 이미지는 클릭 불가 Legal 링크가 없어 표기를 생략합니다.
    var showsLegalAttribution: Bool = true
    /// 상세·저장 카드 등 좁은 지도 프레임용 (기본 1.0 = 1080pt 공유 카드).
    var brandLogoSizeScale: CGFloat = 1
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .overlay(alignment: .bottomLeading) {
                if showsLegalAttribution {
                    RouteMapLegalAttributionOverlay()
                }
            }
            .overlay(alignment: .bottomLeading) {
                if showsBrandLogo {
                    RouteBrandLogoOverlay(
                        bottomInsetOverride: showsLegalAttribution
                            ? RouteMapOverlayMetrics.legalAttributionHeight
                                + RouteMapOverlayMetrics.brandLogoAboveAttributionGap
                            : RouteMapOverlayMetrics.brandLogoCoveringAttributionBottomInset,
                        sizeScale: brandLogoSizeScale
                    )
                }
            }
    }
}

#endif
