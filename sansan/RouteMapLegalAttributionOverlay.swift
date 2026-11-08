//
//  RouteMapLegalAttributionOverlay.swift
//  sansan
//
//  경로 이미지 카드 좌하단 고정 Apple Maps 법적 표기 레이어.
//

#if os(iOS)

import SwiftUI

struct RouteMapLegalAttributionOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let layoutScale = width / RouteMapOverlayMetrics.referenceCanvasWidth
            let stripHeight = RouteMapOverlayMetrics.legalAttributionStripHeight(forCanvasWidth: width)
            let stripWidth = RouteMapOverlayMetrics.scaled(
                RouteMapOverlayMetrics.legalAttributionWidth,
                forCanvasWidth: width
            )
            let leading = RouteMapOverlayMetrics.scaled(
                RouteMapOverlayMetrics.legalAttributionLeading,
                forCanvasWidth: width
            )

            Group {
                if let badge = AppleMapsAttributionImage.raster(referenceWidth: width) {
                    Image(uiImage: badge)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: stripWidth, height: stripHeight, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, leading)
            .padding(.bottom, 0)
            .accessibilityHidden(true)
            .id(layoutScale)
        }
        .allowsHitTesting(false)
    }
}

#endif
