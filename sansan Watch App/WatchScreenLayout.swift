//
//  WatchScreenLayout.swift
//  sansan Watch App
//
//  기기별 화면 크기에 맞춰 메트릭 UI 치수를 스케일합니다.
//

import CoreGraphics

/// 38mm TabView 콘텐츠 영역(162×176pt) 기준.
struct WatchScreenLayout {
    let scale: CGFloat
    let horizontalPadding: CGFloat
    let gridSpacing: CGFloat
    let elapsedFontSize: CGFloat
    let statusFontSize: CGFloat
    let statIconFontSize: CGFloat
    let secondaryLabelFontSize: CGFloat
    let secondaryUnitFontSize: CGFloat
    /// 모든 데이터 값(거리·고도·상승·평균속도·걸음수·칼로리·심박수) 공통 숫자 폰트.
    let statValueFontSize: CGFloat
    let cardCornerRadius: CGFloat
    let cardPaddingH: CGFloat
    let cardPaddingV: CGFloat
    let heartRateCardHeight: CGFloat
    /// 스크롤형 데이터 화면의 메트릭 카드 높이.
    let statCardHeight: CGFloat
    let countdownFontSize: CGFloat

    private static let referenceSize = CGSize(width: 162, height: 176)
    private static let minScale: CGFloat = 0.65
    private static let maxScale: CGFloat = 1.18

    init(size: CGSize) {
        let heightRatio = size.height / Self.referenceSize.height
        let widthRatio = size.width / Self.referenceSize.width
        scale = min(max(min(heightRatio, widthRatio), Self.minScale), Self.maxScale)

        horizontalPadding = 6
        gridSpacing = 3 * scale
        elapsedFontSize = 20 * scale
        statusFontSize = max(8, 9 * scale)
        statIconFontSize = max(8, 9 * scale)
        secondaryLabelFontSize = max(10, 11.7 * scale)
        secondaryUnitFontSize = max(8, 9 * scale)
        statValueFontSize = max(26, 33.8 * scale)
        cardCornerRadius = max(8, 10 * scale)
        cardPaddingH = 5 * scale
        cardPaddingV = 3 * scale
        heartRateCardHeight = 50 * scale
        statCardHeight = 60 * scale
        countdownFontSize = 72 * scale
    }
}
