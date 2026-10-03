//
//  FlythroughHUDLayout.swift
//  sansan
//
//  세로/가로 영상 HUD·카메라 프레이밍에 공통으로 쓰는 여백·패널 크기.
//

#if os(iOS)

import CoreGraphics
import CoreLocation
import UIKit

enum FlythroughHUDLayout {
    struct Metrics {
        let titleTopInset: CGFloat
        let mapTopInset: CGFloat
        let horizontalInset: CGFloat
        let bottomMargin: CGFloat
        let profileHeight: CGFloat
        let statsPanelWidth: CGFloat
        let statsPanelTopInset: CGFloat
        let statsPanelBottomInset: CGFloat

        var profileBottomInset: CGFloat {
            bottomMargin + profileHeight
        }

        /// 지도가 실제로 보여야 하는 영역(HUD 제외) — 카메라 프레이밍용.
        var mapInsets: UIEdgeInsets {
            switch orientation {
            case .portrait:
                return UIEdgeInsets(
                    top: mapTopInset,
                    left: horizontalInset,
                    bottom: profileBottomInset + statsBlockHeight,
                    right: horizontalInset
                )
            case .landscape:
                return UIEdgeInsets(
                    top: mapTopInset,
                    left: horizontalInset,
                    bottom: profileBottomInset + 10,
                    right: horizontalInset + statsPanelWidth + 14
                )
            }
        }

        private let orientation: FlythroughOrientation

        /// 세로 영상 하단 통계 2행 높이(거리·상승·시간 + 걸음·심박·칼로리).
        var statsBlockHeight: CGFloat {
            switch orientation {
            case .portrait: return 120
            case .landscape: return 0
            }
        }

        /// 세로 — `drawPortraitBottomHUD` 고도 그래프 상단까지(통계 행 제외).
        var portraitElevationProfileTopFromBottom: CGFloat {
            bottomMargin + 34 + 52 + 28 + profileHeight
        }

        /// 가로 — 고도 그래프 상단까지.
        var landscapeElevationProfileTopFromBottom: CGFloat {
            bottomMargin + profileHeight
        }

        /// 탑뷰 전체 경로 프레이밍 — HUD·제목·고도 그래프와 겹치지 않는 가용 영역(적당한 여백).
        func finalRouteMapInsets(canvasSize: CGSize) -> UIEdgeInsets {
            switch orientation {
            case .portrait:
                return UIEdgeInsets(
                    top: mapTopInset + 10,
                    left: horizontalInset + 14,
                    bottom: portraitElevationProfileTopFromBottom + 32,
                    right: horizontalInset + 14
                )
            case .landscape:
                let titleClearance = canvasSize.width * 0.14
                return UIEdgeInsets(
                    top: mapTopInset + 12,
                    left: horizontalInset + titleClearance + 8,
                    bottom: landscapeElevationProfileTopFromBottom + 32,
                    right: horizontalInset + statsPanelWidth + 32
                )
            }
        }

        /// 탑뷰 줌 거리 계산용 — 경로 끝·라벨이 잘리지 않게 여백을 추가합니다.
        func finalRouteFitInsets(canvasSize: CGSize) -> UIEdgeInsets {
            let base = finalRouteMapInsets(canvasSize: canvasSize)
            switch orientation {
            case .portrait:
                return UIEdgeInsets(
                    top: base.top + 22,
                    left: base.left + 16,
                    bottom: base.bottom + 20,
                    right: base.right + 16
                )
            case .landscape:
                return UIEdgeInsets(
                    top: base.top + 18,
                    left: base.left + 8,
                    bottom: base.bottom + 12,
                    right: base.right + 18
                )
            }
        }

        /// 세로 비행·탑뷰 가용 영역 — 타이틀 아래~고도 그래프 위(첫 번째 붉은 영역).
        func portraitFlightMapInsets(canvasSize: CGSize) -> UIEdgeInsets {
            finalRouteMapInsets(canvasSize: canvasSize)
        }

        /// 가로 탑뷰 대각(좌하→우상) — 화면 '위'에서 시계방향 각도(°).
        func landscapeFinalRouteDiagonalAngleFromScreenUp(canvasSize: CGSize) -> CLLocationDirection {
            let insets = finalRouteMapInsets(canvasSize: canvasSize)
            let usableWidth = max(canvasSize.width - insets.left - insets.right, 1)
            let usableHeight = max(canvasSize.height - insets.top - insets.bottom, 1)
            return CLLocationDirection(atan2(Double(usableWidth), Double(usableHeight)) * 180 / .pi)
        }

        /// 세로 탑뷰 장축 각도 — 두 번째 붉은 영역(세로축에서 시계방향 기울기, °).
        func portraitFinalRouteAxisAngleFromScreenUp(canvasSize: CGSize) -> CLLocationDirection {
            let insets = finalRouteMapInsets(canvasSize: canvasSize)
            let usableWidth = max(canvasSize.width - insets.left - insets.right, 1)
            let usableHeight = max(canvasSize.height - insets.top - insets.bottom, 1)
            let boxDiagonal = atan2(Double(usableWidth), Double(usableHeight)) * 180 / .pi
            // 스크린샷 2번째 붉은 영역 ≈ 17°. 기기 비율에 따라 미세 조정(완만한 대각).
            let tilt = 17.0 + min(max((boxDiagonal - 32.0) * 0.12, -3.0), 3.0)
            return CLLocationDirection(tilt)
        }

        /// 비행 중 가로모드 가용 영역 — 통계 패널·제목을 피한 가로 비행대.
        func landscapeFlightMapInsets(canvasSize: CGSize) -> UIEdgeInsets {
            let titleClearance = canvasSize.width * 0.18
            return UIEdgeInsets(
                top: mapTopInset + 6,
                left: horizontalInset + titleClearance,
                bottom: profileBottomInset + 14,
                right: horizontalInset + statsPanelWidth + 20
            )
        }

        /// 활성화 영역(타이틀 아래~고도 그래프 위) — 세로 비행·탑뷰 프레이밍용.
        func activeAreaInsets(canvasSize: CGSize) -> UIEdgeInsets {
            switch orientation {
            case .portrait:
                return portraitFlightMapInsets(canvasSize: canvasSize)
            case .landscape:
                return landscapeFlightMapInsets(canvasSize: canvasSize)
            }
        }

        /// 활성화 영역 중심(화면 좌표).
        func activeAreaTargetCenter(canvasSize: CGSize) -> CGPoint {
            let insets = activeAreaInsets(canvasSize: canvasSize)
            let usableWidth = max(canvasSize.width - insets.left - insets.right, 1)
            let usableHeight = max(canvasSize.height - insets.top - insets.bottom, 1)
            return CGPoint(
                x: insets.left + usableWidth / 2,
                y: insets.top + usableHeight / 2
            )
        }

        /// 탑뷰 가용 영역(붉은 영역) 가로·세로 중심.
        func finalRouteTargetCenter(canvasSize: CGSize) -> CGPoint {
            activeAreaTargetCenter(canvasSize: canvasSize)
        }

        /// 탑뷰 가용 영역(붉은 영역) 좌하→우상 대각선 — 화면 '위'에서 시계방향 각도(°).
        func finalRouteDiagonalAngleFromScreenUp(canvasSize: CGSize) -> CLLocationDirection {
            switch orientation {
            case .landscape:
                return landscapeFinalRouteDiagonalAngleFromScreenUp(canvasSize: canvasSize)
            case .portrait:
                return portraitFinalRouteAxisAngleFromScreenUp(canvasSize: canvasSize)
            }
        }

        fileprivate init(
            orientation: FlythroughOrientation,
            titleTopInset: CGFloat,
            mapTopInset: CGFloat,
            horizontalInset: CGFloat,
            bottomMargin: CGFloat,
            profileHeight: CGFloat,
            statsPanelWidth: CGFloat,
            statsPanelTopInset: CGFloat = 0,
            statsPanelBottomInset: CGFloat = 0
        ) {
            self.orientation = orientation
            self.titleTopInset = titleTopInset
            self.mapTopInset = mapTopInset
            self.horizontalInset = horizontalInset
            self.bottomMargin = bottomMargin
            self.profileHeight = profileHeight
            self.statsPanelWidth = statsPanelWidth
            self.statsPanelTopInset = statsPanelTopInset
            self.statsPanelBottomInset = statsPanelBottomInset
        }
    }

    static func metrics(
        canvasSize: CGSize,
        orientation: FlythroughOrientation
    ) -> Metrics {
        switch orientation {
        case .portrait:
            return Metrics(
                orientation: .portrait,
                titleTopInset: 54,
                mapTopInset: 100,
                horizontalInset: 22,
                bottomMargin: 54,
                profileHeight: 44,
                statsPanelWidth: 0,
                statsPanelTopInset: 0,
                statsPanelBottomInset: 0
            )
        case .landscape:
            let profileHeight = max(36, (canvasSize.height * 0.17).rounded())
            let baseStatsWidth = max(128, (canvasSize.width * 0.24).rounded())
            let statsPanelWidth = (baseStatsWidth * 2 / 3).rounded()
            let statsPanelTopInset = max(24, (canvasSize.height * 0.055).rounded())
            let statsPanelBottomInset = max(22, (canvasSize.height * 0.05).rounded())
            return Metrics(
                orientation: .landscape,
                titleTopInset: 18,
                mapTopInset: 52,
                horizontalInset: 18,
                bottomMargin: 10,
                profileHeight: profileHeight,
                statsPanelWidth: statsPanelWidth,
                statsPanelTopInset: statsPanelTopInset,
                statsPanelBottomInset: statsPanelBottomInset
            )
        }
    }

    /// HUD를 제외한 지도 가용 영역의 화면 중심에 경로가 오도록 look-at을 동쪽으로 이동(미터).
    static func landscapeCameraLateralOffsetMeters(
        layout: Metrics,
        canvasSize: CGSize,
        cameraDistance: CLLocationDistance
    ) -> CLLocationDistance {
        guard layout.statsPanelWidth > 0, canvasSize.width > 0 else { return 0 }
        let distance = max(cameraDistance, 500)
        let rightGutter = layout.horizontalInset + 14
        let usableWidth = canvasSize.width - layout.horizontalInset - layout.statsPanelWidth - rightGutter
        guard usableWidth > 0 else { return 0 }
        let usableCenterX = layout.horizontalInset + usableWidth / 2
        let screenCenterX = canvasSize.width / 2
        let screenShift = max(screenCenterX - usableCenterX, 0)
        let fraction = screenShift / canvasSize.width
        return distance * Double(fraction) * 0.92
    }

    /// HUD를 제외한 지도 가용 영역 중심에 맞추기 위해 look-at을 동쪽·(선택) 남쪽으로 이동합니다.
    static func landscapeLookAtCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        layout: Metrics,
        canvasSize: CGSize,
        cameraDistance: CLLocationDistance,
        routeSpanMeters: CLLocationDistance = 0,
        clearProfileOverlap: Bool = false
    ) -> CLLocationCoordinate2D {
        var result = coordinate
        let lateral = landscapeCameraLateralOffsetMeters(
            layout: layout,
            canvasSize: canvasSize,
            cameraDistance: cameraDistance
        )
        if lateral > 0 {
            result = FlythroughGeo.offset(result, meters: lateral, bearingDegrees: 90)
        }
        if clearProfileOverlap {
            let vertical = landscapeCameraVerticalOffsetMeters(
                layout: layout,
                canvasSize: canvasSize,
                cameraDistance: cameraDistance,
                routeSpanMeters: routeSpanMeters
            )
            if vertical > 0 {
                result = FlythroughGeo.offset(result, meters: vertical, bearingDegrees: 180)
            }
            let west = landscapeCameraWestOffsetMeters(
                cameraDistance: cameraDistance,
                routeSpanMeters: routeSpanMeters
            )
            if west > 0 {
                result = FlythroughGeo.offset(result, meters: west, bearingDegrees: 270)
            }
        }
        return result
    }

    /// 최종 경로 전경 look-at을 서쪽으로 살짝 이동(미터).
    static func landscapeCameraWestOffsetMeters(
        cameraDistance: CLLocationDistance,
        routeSpanMeters: CLLocationDistance
    ) -> CLLocationDistance {
        let distance = max(cameraDistance, 500)
        let baseOffset = distance * 0.022
        guard routeSpanMeters > 20 else { return baseOffset }
        return min(max(baseOffset, routeSpanMeters * 0.012), routeSpanMeters * 0.05)
    }

    /// 화면 기준 방향(위=0·아래=180·좌=270·우=90)을 카메라 heading이 적용된 월드 방위로 변환합니다.
    static func screenRelativeBearing(
        cameraHeading: CLLocationDirection,
        screenBearing: CLLocationDirection
    ) -> CLLocationDirection {
        (cameraHeading + screenBearing + 360).truncatingRemainder(dividingBy: 360)
    }

    /// 탑뷰(pitch 0) 수직 FOV 50° 기준 — 화면 세로 1 대비 지도 미터 환산 계수(2·tan 25°).
    static let topViewMetersPerCanvasHeightFactor: Double = 0.9326

    /// 탑뷰에서 화면 1pt가 지도에서 차지하는 미터.
    static func topViewMetersPerPoint(
        cameraDistance: CLLocationDistance,
        canvasHeight: CGFloat
    ) -> Double {
        guard canvasHeight > 0 else { return 0 }
        return cameraDistance * topViewMetersPerCanvasHeightFactor / Double(canvasHeight)
    }

    /// 최종 전경 look-at — 경로의 화면 기준 바운딩 박스 중심(`routeScreenFrameCenter`)이
    /// 가용 영역(`finalRouteTargetCenter`) 중앙에 정확히 오도록 계산합니다.
    static func finalRouteLookAt(
        routeScreenFrameCenter: CLLocationCoordinate2D,
        layout: Metrics,
        canvasSize: CGSize,
        cameraDistance: CLLocationDistance,
        cameraHeading: CLLocationDirection
    ) -> CLLocationCoordinate2D {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return routeScreenFrameCenter }
        let target = layout.finalRouteTargetCenter(canvasSize: canvasSize)
        let dx = Double(target.x - canvasSize.width / 2)
        let dy = Double(target.y - canvasSize.height / 2)
        let metersPerPoint = topViewMetersPerPoint(
            cameraDistance: max(cameraDistance, 500),
            canvasHeight: canvasSize.height
        )

        var result = routeScreenFrameCenter
        let horizontalMeters = abs(dx) * metersPerPoint
        if horizontalMeters > 1 {
            result = FlythroughGeo.offset(
                result,
                meters: horizontalMeters,
                bearingDegrees: screenRelativeBearing(
                    cameraHeading: cameraHeading,
                    screenBearing: dx >= 0 ? 270 : 90
                )
            )
        }
        let verticalMeters = abs(dy) * metersPerPoint
        if verticalMeters > 1 {
            result = FlythroughGeo.offset(
                result,
                meters: verticalMeters,
                bearingDegrees: screenRelativeBearing(
                    cameraHeading: cameraHeading,
                    screenBearing: dy >= 0 ? 0 : 180
                )
            )
        }
        return result
    }

    /// 탑뷰 카메라에서 좌표를 캔버스 화면 pt로 투영합니다(look-at = 화면 중심).
    static func topViewScreenPoint(
        for coordinate: CLLocationCoordinate2D,
        lookAt: CLLocationCoordinate2D,
        cameraDistance: CLLocationDistance,
        cameraHeading: CLLocationDirection,
        canvasSize: CGSize
    ) -> CGPoint {
        let metersPerPoint = topViewMetersPerPoint(
            cameraDistance: max(cameraDistance, 500),
            canvasHeight: canvasSize.height
        )
        guard metersPerPoint > 0 else {
            return CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        }

        let latScale = 111_320.0
        let lonScale = 111_320.0 * cos(lookAt.latitude * .pi / 180)
        let eastMeters = (coordinate.longitude - lookAt.longitude) * lonScale
        let northMeters = (coordinate.latitude - lookAt.latitude) * latScale
        let headingRadians = -cameraHeading * .pi / 180
        let cosH = cos(headingRadians)
        let sinH = sin(headingRadians)
        let screenEast = eastMeters * cosH - northMeters * sinH
        let screenNorth = eastMeters * sinH + northMeters * cosH

        return CGPoint(
            x: canvasSize.width / 2 + CGFloat(screenEast / metersPerPoint),
            y: canvasSize.height / 2 - CGFloat(screenNorth / metersPerPoint)
        )
    }

    /// 세로 비행 look-at — 활성화 영역 중앙에 경로가 오도록 이동합니다.
    static func portraitActiveAreaLookAt(
        _ coordinate: CLLocationCoordinate2D,
        layout: Metrics,
        canvasSize: CGSize,
        cameraDistance: CLLocationDistance,
        routeSpanMeters: CLLocationDistance = 0
    ) -> CLLocationCoordinate2D {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return coordinate }
        let distance = max(cameraDistance, 500)
        let target = layout.activeAreaTargetCenter(canvasSize: canvasSize)
        let screenCenterX = canvasSize.width / 2
        let screenCenterY = canvasSize.height / 2

        var result = coordinate

        let horizontalDelta = Double((target.x - screenCenterX) / canvasSize.width)
        let horizontalMeters = distance * abs(horizontalDelta) * 0.94
        if horizontalMeters > 1 {
            result = FlythroughGeo.offset(
                result,
                meters: horizontalMeters,
                bearingDegrees: horizontalDelta >= 0 ? 270 : 90
            )
        }

        let verticalDelta = Double(screenCenterY - target.y)
        var verticalMeters = distance * abs(verticalDelta) / Double(canvasSize.height) * 0.94
        if routeSpanMeters > 20 {
            verticalMeters = min(verticalMeters, routeSpanMeters * 0.26)
        }
        if verticalMeters > 1 {
            result = FlythroughGeo.offset(
                result,
                meters: verticalMeters,
                bearingDegrees: verticalDelta >= 0 ? 180 : 0
            )
        }
        return result
    }

    /// 세로 비행 look-at — 고도 그래프·통계 아래까지 제외한 영역 중앙.
    static func portraitRouteLookAt(
        _ coordinate: CLLocationCoordinate2D,
        layout: Metrics,
        canvasSize: CGSize,
        cameraDistance: CLLocationDistance,
        routeSpanMeters: CLLocationDistance = 0
    ) -> CLLocationCoordinate2D {
        portraitActiveAreaLookAt(
            coordinate,
            layout: layout,
            canvasSize: canvasSize,
            cameraDistance: cameraDistance,
            routeSpanMeters: routeSpanMeters
        )
    }

    /// 고도 그래프와 겹치지 않도록 look-at을 남쪽으로 이동(미터). 경로 세로 길이에 비례해 제한.
    static func landscapeCameraVerticalOffsetMeters(
        layout: Metrics,
        canvasSize: CGSize,
        cameraDistance: CLLocationDistance,
        routeSpanMeters: CLLocationDistance
    ) -> CLLocationDistance {
        guard canvasSize.height > 0 else { return 0 }
        let distance = max(cameraDistance, 500)

        let usableTop = layout.mapTopInset
        let usableBottom = canvasSize.height - layout.profileBottomInset - 10
        let usableCenterY = usableTop + (usableBottom - usableTop) / 2
        let screenCenterY = canvasSize.height / 2
        let screenShiftY = max(screenCenterY - usableCenterY, 0)

        var offset = distance * Double(screenShiftY / canvasSize.height) * 0.72

        let profileBand = layout.profileBottomInset + 10
        offset += distance * Double(profileBand / canvasSize.height) * 0.18

        guard routeSpanMeters > 20 else { return offset }
        let minLift = routeSpanMeters * 0.035
        let maxLift = routeSpanMeters * 0.11
        return min(max(offset, minLift), maxLift)
    }

    /// 가로·세로 영상에서 지도 주석(거리·사진) 크기 배율.
    static func mapMarkerContentScale(orientation: FlythroughOrientation) -> CGFloat {
        switch orientation {
        case .portrait: return 1.0
        case .landscape: return 0.72
        }
    }

    static func photoMarkerContentScale(orientation: FlythroughOrientation) -> CGFloat {
        switch orientation {
        case .portrait: return 1.0
        case .landscape: return 0.60
        }
    }

    /// @deprecated flightCenterOffsetMeters — 호환용, east look-at만 사용.
    static func flightCenterOffsetMeters(
        layout: Metrics,
        canvasSize: CGSize,
        cameraDistance: CLLocationDistance,
        heading: CLLocationDirection
    ) -> (lateral: CLLocationDistance, backward: CLLocationDistance) {
        let lateral = landscapeCameraLateralOffsetMeters(
            layout: layout,
            canvasSize: canvasSize,
            cameraDistance: cameraDistance
        )
        return (lateral: lateral, backward: 0)
    }
}

#endif
