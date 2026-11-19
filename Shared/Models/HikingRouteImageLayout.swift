//
//  HikingRouteImageLayout.swift
//  Shared
//

import CoreGraphics

/// 기록 상세 지도·경로 PNG 스냅샷 공통 비율 (상세 화면과 동일한 뷰포트 제한).
enum HikingRouteImageLayout {
    static let referenceContentWidth: CGFloat = 377
    static let referenceViewportHeight: CGFloat = 780
    static let detailMapMaxViewportFraction: CGFloat = 0.48
    static let exportWidth: CGFloat = 1080
    /// 경로 바운딩 박스가 경로 카드 가로·세로를 채우는 비율.
    /// 기존 0.6(좌우 여백 합 40%)에서 여백을 반으로 줄여 경로에 넘깁니다.
    static let routeCardFillFraction: CGFloat = 0.8

    /// 기록 상세 `HikingRecordRouteMapView`와 동일한 지도 높이.
    static func detailMapHeight(forWidth width: CGFloat) -> CGFloat {
        min(width * 4 / 3, referenceViewportHeight * detailMapMaxViewportFraction)
    }

    /// SwiftUI Map 캡처용 — 상세 화면 지도와 동일 pt (녹지 타일 LOD 일치).
    static var captureSize: CGSize {
        CGSize(
            width: referenceContentWidth,
            height: detailMapHeight(forWidth: referenceContentWidth)
        )
    }

    /// MKMapView 표기 스트립 — `RouteMapOverlayMetrics`와 동일( watch 타겟 호환).
    private static func attributionStripHeight(forMapWidth width: CGFloat) -> CGFloat {
        max(34 * (width / 1080), 40)
    }

    /// 경로 PNG — 상세 지도와 같은 종횡비 (표기 스트립 제외).
    static var exportSize: CGSize {
        let referenceHeight = detailMapHeight(forWidth: referenceContentWidth)
        let fullHeight = exportWidth * referenceHeight / referenceContentWidth
        let strip = attributionStripHeight(forMapWidth: exportWidth)
        return CGSize(width: exportWidth, height: max(fullHeight - strip, 1))
    }
}
