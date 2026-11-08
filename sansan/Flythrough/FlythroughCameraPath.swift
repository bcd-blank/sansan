//
//  FlythroughCameraPath.swift
//  sansan
//
//  경로를 따라가는 3D 카메라 키프레임 생성. 비행(경로 추적) → 아웃트로(전경) 2단계.
//  계약: FlythroughPipelineContract.swift
//

#if os(iOS)

import CoreLocation
import Foundation
import MapKit
import UIKit

enum FlythroughPhase {
    case intro
    case flight
    case outro
}

/// 인트로 타이밍 — 카메라 줌·타이틀 페이드가 같은 phaseFraction 구간을 공유합니다.
enum FlythroughIntroTiming {
    /// 타이틀 페이드인 종료(0~1).
    static let titleFadeInEnd: Double = 0.10
    /// 타이틀 페이드아웃·시작점 줌인 시작.
    static let zoomStart: Double = 0.30
    /// 타이틀 페이드아웃 종료.
    static let titleFadeOutEnd: Double = 0.72

    static func zoomProgress(phaseFraction: Double) -> Double {
        guard phaseFraction > zoomStart else { return 0 }
        let raw = (phaseFraction - zoomStart) / (1 - zoomStart)
        return min(max(raw, 0), 1)
    }
}

/// 비행 시작 직후 — 시작점에서 머리 마커 깜박임 타이밍.
enum FlythroughFlightStartTiming {
    static let blinkCount = 3

    static func headBlinkOpacity(frame: Int, totalFrames: Int) -> CGFloat {
        guard totalFrames > 1 else { return 1 }
        if frame >= totalFrames - 1 { return 1 }
        let holdFraction = Double(frame) / Double(max(totalFrames - 1, 1))
        let cycle = holdFraction * Double(blinkCount)
        let phase = cycle - floor(cycle)
        return phase < 0.5 ? 1 : 0
    }
}

    /// 한 프레임에 대응하는 카메라·진행률·단계 지시.
struct FlythroughFrameDirective {
    let camera: MKMapCamera
    /// 경로 진행률(0~1). 오버레이가 사용.
    let progress: Double
    let phase: FlythroughPhase
    /// 인트로/아웃트로 내부 진행률(0~1) — 타이틀 페이드 등에 사용.
    let phaseFraction: Double
    /// 직전 프레임과 동일한 합성 결과를 재사용(아웃트로 고정 구간 등).
    let reusesPreviousFrame: Bool
    /// 비행 머리 마커 불투명도(0~1). 시작점 깜박임에 사용.
    let headMarkerOpacity: CGFloat
    /// 시작 지점 라벨(아이콘+텍스트) 1회 표시.
    let showsStartEndpointLabel: Bool
    /// 종료 지점 라벨(아이콘+텍스트) 1회 표시.
    let showsEndEndpointLabel: Bool

    init(
        camera: MKMapCamera,
        progress: Double,
        phase: FlythroughPhase,
        phaseFraction: Double,
        reusesPreviousFrame: Bool,
        headMarkerOpacity: CGFloat = 1,
        showsStartEndpointLabel: Bool = false,
        showsEndEndpointLabel: Bool = false
    ) {
        self.camera = camera
        self.progress = progress
        self.phase = phase
        self.phaseFraction = phaseFraction
        self.reusesPreviousFrame = reusesPreviousFrame
        self.headMarkerOpacity = headMarkerOpacity
        self.showsStartEndpointLabel = showsStartEndpointLabel
        self.showsEndEndpointLabel = showsEndEndpointLabel
    }
}

@MainActor
enum FlythroughCameraPath {
    static func build(
        route: FlythroughRoute,
        configuration: FlythroughVideoConfiguration,
        canvasSize: CGSize
    ) -> [FlythroughFrameDirective] {
        let fps = max(configuration.framesPerSecond, 1)
        let introFrames = configuration.introDuration > 0
            ? max(Int(configuration.introDuration * Double(fps)), 1)
            : 0
        let flightFrames = max(Int(configuration.flightDuration * Double(fps)), 1)
        let outroFrames = max(Int(configuration.outroDuration * Double(fps)), 1)

        let establishing = establishingParameters(
            route: route,
            canvasSize: canvasSize,
            configuration: configuration
        )

        // 비행 구간 — 가로·세로 프레이밍·헤딩을 분리합니다.
        let isLandscape = configuration.orientation == .landscape
        let layout = FlythroughHUDLayout.metrics(
            canvasSize: canvasSize,
            orientation: configuration.orientation
        )
        let routeStart = route.coordinates.first ?? CLLocationCoordinate2D()
        let longAxis = routeLongAxis(for: route.coordinates, routeStart: routeStart)
        let routeHeading = dominantRouteHeading(route.coordinates)
        let flightHeading = flightCameraHeading(
            routeHeading: routeHeading,
            longAxis: longAxis,
            layout: layout,
            canvasSize: canvasSize,
            isLandscape: isLandscape
        )
        var flightProgress: [Double] = []
        flightProgress.reserveCapacity(flightFrames)
        var rawFlight: [CameraParameters] = []
        rawFlight.reserveCapacity(flightFrames)
        for frame in 0..<flightFrames {
            let raw = Double(frame) / Double(max(flightFrames - 1, 1))
            let progress = easeInOutMild(raw)
            flightProgress.append(progress)
            rawFlight.append(
                flightParameters(
                    route: route,
                    progress: progress,
                    configuration: configuration,
                    canvasSize: canvasSize,
                    heading: flightHeading
                )
            )
        }
        var rawDistances = rawFlight.map(\.distance)
        rawDistances = stabilizedFlightDistances(progress: flightProgress, rawDistances: rawDistances)
        rawDistances = progressScaledFlightDistances(
            progress: flightProgress,
            distances: rawDistances,
            isLandscape: isLandscape
        )
        let constantPitch = flightPitch(isLandscape: isLandscape)
        for index in rawFlight.indices {
            rawFlight[index].distance = rawDistances[index]
            rawFlight[index].pitch = constantPitch
        }
        var flight = stabilizeFlightCenters(
            rawFlight,
            fps: fps,
            isPortrait: !isLandscape
        )
        if !isLandscape {
            flight = anchorPortraitActiveAreaStart(
                route: route,
                params: flight,
                canvasSize: canvasSize,
                fps: fps
            )
        }

        let flightStart = flight.first
            ?? flightParameters(
                route: route,
                progress: 0,
                configuration: configuration,
                canvasSize: canvasSize,
                heading: flightHeading
            )
        let flightEnd = flight.last
            ?? flightParameters(
                route: route,
                progress: 1,
                configuration: configuration,
                canvasSize: canvasSize,
                heading: flightHeading
            )

        let startHoldFrames = FlythroughPipelineInvariant.flightStartHoldBeforeFlight
            ? max(Int(FlythroughPipelineTuning.flightStartHoldDuration * Double(fps)), 1)
            : 0
        let endHoldFrames = FlythroughPipelineInvariant.flightEndHoldBeforeOutro
            ? max(Int(FlythroughPipelineTuning.flightEndHoldDuration * Double(fps)), 1)
            : 0

        var directives: [FlythroughFrameDirective] = []
        directives.reserveCapacity(
            introFrames + startHoldFrames + flightFrames + endHoldFrames + outroFrames
        )

        // 인트로 — 전경(탑뷰) → 타이틀 페이드아웃 + 시작점 줌인 → 비행.
        if introFrames > 0 {
            for frame in 0..<introFrames {
                let phaseFraction = Double(frame) / Double(max(introFrames - 1, 1))
                let zoomProgress = FlythroughIntroTiming.zoomProgress(phaseFraction: phaseFraction)
                let params: CameraParameters
                if zoomProgress <= 0 {
                    params = establishing
                } else {
                    params = introZoomParameters(
                        from: establishing,
                        to: flightStart,
                        zoomProgress: zoomProgress,
                        configuration: configuration
                    )
                }
                directives.append(
                    FlythroughFrameDirective(
                        camera: params.makeCamera(),
                        progress: 0,
                        phase: .intro,
                        phaseFraction: phaseFraction,
                        reusesPreviousFrame: false
                    )
                )
            }
        }

        // 비행 시작 — 시작점에서 머리 마커를 깜박인 뒤 경로 추적. 시작 라벨은 홀드 구간에만 표시.
        if startHoldFrames > 0 {
            let holdCamera = flightStart.makeCamera()
            for frame in 0..<startHoldFrames {
                directives.append(
                    FlythroughFrameDirective(
                        camera: holdCamera,
                        progress: 0,
                        phase: .flight,
                        phaseFraction: 0,
                        reusesPreviousFrame: false,
                        headMarkerOpacity: FlythroughFlightStartTiming.headBlinkOpacity(
                            frame: frame,
                            totalFrames: startHoldFrames
                        ),
                        showsStartEndpointLabel: true
                    )
                )
            }
        }

        // 비행: 스무딩된 카메라로 경로 추적.
        for frame in 0..<flightFrames {
            directives.append(
                FlythroughFrameDirective(
                    camera: flight[frame].makeCamera(),
                    progress: flightProgress[frame],
                    phase: .flight,
                    phaseFraction: Double(frame) / Double(max(flightFrames - 1, 1)),
                    reusesPreviousFrame: false
                )
            )
        }

        // 비행 종료 — 마지막 카메라·progress=1 고정 후 아웃트로(기울기·경로 전환 끊김 방지).
        if endHoldFrames > 0 {
            for frame in 0..<endHoldFrames {
                directives.append(
                    FlythroughFrameDirective(
                        camera: flightEnd.makeCamera(),
                        progress: 1,
                        phase: .flight,
                        phaseFraction: 1,
                        reusesPreviousFrame: frame > 0
                    )
                )
            }
        }

        // 아웃트로: 3초 줌아웃 → 9초 전체 경로 고정 노출.
        let transitionFrames = max(Int(configuration.outroTransitionDuration * Double(fps)), 1)
        let holdFrames = max(Int(configuration.outroHoldDuration * Double(fps)), 1)
        let transitionFraction = configuration.outroTransitionFraction
        for frame in 0..<transitionFrames {
            let raw = Double(frame) / Double(max(transitionFrames - 1, 1))
            let t = easeInOut(raw)
            let params = outroTransitionParameters(
                from: flightEnd,
                to: establishing,
                easedProgress: t,
                isLandscape: isLandscape
            )
            directives.append(
                FlythroughFrameDirective(
                    camera: params.makeCamera(),
                    progress: 1,
                    phase: .outro,
                    phaseFraction: raw * transitionFraction,
                    reusesPreviousFrame: false
                )
            )
        }
        for frame in 0..<holdFrames {
            let holdFraction = Double(frame) / Double(max(holdFrames - 1, 1))
            directives.append(
                FlythroughFrameDirective(
                    camera: establishing.makeCamera(),
                    progress: 1,
                    phase: .outro,
                    phaseFraction: transitionFraction
                        + holdFraction * (1 - transitionFraction),
                    reusesPreviousFrame: frame > 0,
                    showsEndEndpointLabel: frame == 0
                )
            )
        }

        return directives
    }

    /// 카메라 look-at — 큰 방향은 따라가고 GPS 미세 지터만 제거(지연·멈칫 없음).
    private static func stabilizeFlightCenters(
        _ params: [CameraParameters],
        fps: Int,
        isPortrait: Bool
    ) -> [CameraParameters] {
        guard params.count > 1 else { return params }
        let window = isPortrait
            ? max(1, Int(Double(fps) * 0.42))
            : max(1, Int(Double(fps) * 0.85))
        return zeroPhaseSmoothCenters(params, window: window)
    }

    /// 세로 비행 초반 — 시작점이 활성화 영역 안에 오도록 look-at을 고정·완화합니다.
    private static func anchorPortraitActiveAreaStart(
        route: FlythroughRoute,
        params: [CameraParameters],
        canvasSize: CGSize,
        fps: Int
    ) -> [CameraParameters] {
        guard let routeStart = route.coordinates.first, !params.isEmpty else { return params }

        let layout = FlythroughHUDLayout.metrics(
            canvasSize: canvasSize,
            orientation: .portrait
        )
        let anchorFrames = max(Int(Double(fps) * 0.55), 1)
        let startDistance = params[0].distance
        let startLookAt = FlythroughHUDLayout.portraitActiveAreaLookAt(
            routeStart,
            layout: layout,
            canvasSize: canvasSize,
            cameraDistance: startDistance,
            routeSpanMeters: routeNorthSouthSpanMeters(for: route.coordinates)
        )

        var result = params
        for index in 0..<min(anchorFrames, result.count) {
            let raw = Double(index) / Double(max(anchorFrames - 1, 1))
            let mix = raw * raw * (3 - 2 * raw)
            result[index].center = FlythroughGeo.interpolate(
                from: startLookAt,
                to: result[index].center,
                fraction: mix
            )
            result[index].distance = max(result[index].distance, startDistance)
        }
        return result
    }

    /// 양방향 이동평균 — 전체 경로를 미리 알 때 지연 없이 부드럽게 만듭니다.
    private static func zeroPhaseSmoothCenters(
        _ params: [CameraParameters],
        window: Int
    ) -> [CameraParameters] {
        let forward = smoothCenters(params, window: window)
        return smoothCenters(Array(forward.reversed()), window: window).reversed()
    }

    /// 비행 프레이밍 — 현재 위치(헤드)와 직전 궤적 중심.
    private static func flightFramingCoordinates(
        route: FlythroughRoute,
        progress: Double
    ) -> [CLLocationCoordinate2D] {
        let clamped = min(max(progress, 0), 1)
        let head = route.cameraLookAtCoordinate(at: clamped)
        var coordinates = [head]

        if clamped < 0.22, let routeStart = route.coordinates.first {
            appendCoordinateIfDistinct(&coordinates, routeStart)
        }

        let headDistance = clamped * route.totalProgressDistance
        let trailWindow: CLLocationDistance = 380
        let trailStart = max(0, headDistance - trailWindow)
        let recentTrail = route.coordinates(fromDistance: trailStart, toDistance: headDistance)
        for coordinate in recentTrail {
            appendCoordinateIfDistinct(&coordinates, coordinate)
        }

        if clamped < 0.97 {
            let lookahead = min(0.035, max(0.010, (1 - clamped) * 0.05))
            let ahead = route.sample(at: min(clamped + lookahead, 1)).coordinate
            appendCoordinateIfDistinct(&coordinates, ahead)
        }

        return coordinates
    }

    private static func appendCoordinateIfDistinct(
        _ coordinates: inout [CLLocationCoordinate2D],
        _ candidate: CLLocationCoordinate2D,
        minDistanceMeters: CLLocationDistance = 1
    ) {
        guard coordinates.allSatisfy({
            FlythroughGeo.distance($0, candidate) > minDistanceMeters
        }) else { return }
        coordinates.append(candidate)
    }

    /// HUD look-at 이동분만큼 여유 좌표를 추가해 프레이밍 거리를 보정합니다.
    private static func flightFramingHUDPadding(
        route: FlythroughRoute,
        coordinates: [CLLocationCoordinate2D],
        progress: Double,
        layout: FlythroughHUDLayout.Metrics,
        canvasSize: CGSize,
        cameraDistance: CLLocationDistance,
        isLandscape: Bool
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 2 else { return coordinates }
        let rect = HikingMapRegion.routeBoundingMapRect(for: coordinates)
        guard !rect.isNull else { return coordinates }

        var padded = coordinates
        let routeSpan = routeNorthSouthSpanMeters(for: coordinates)

        if isLandscape {
            let lateral = FlythroughHUDLayout.landscapeCameraLateralOffsetMeters(
                layout: layout,
                canvasSize: canvasSize,
                cameraDistance: cameraDistance
            )
            if lateral > 0 {
                let westEdge = MKMapPoint(x: rect.minX, y: rect.midY).coordinate
                padded.append(
                    FlythroughGeo.offset(westEdge, meters: lateral * 0.95, bearingDegrees: 270)
                )
            }

            if progress >= 0.88 {
                let vertical = FlythroughHUDLayout.landscapeCameraVerticalOffsetMeters(
                    layout: layout,
                    canvasSize: canvasSize,
                    cameraDistance: cameraDistance,
                    routeSpanMeters: routeSpan
                )
                if vertical > 0 {
                    let southEdge = MKMapPoint(x: rect.midX, y: rect.minY).coordinate
                    padded.append(
                        FlythroughGeo.offset(southEdge, meters: vertical * 0.82, bearingDegrees: 180)
                    )
                }
            }
        } else {
            if progress < 0.22, let routeStart = route.coordinates.first {
                appendCoordinateIfDistinct(&padded, routeStart)
            }

            let targetTop = layout.mapTopInset
            let targetBottom = canvasSize.height - layout.profileBottomInset - layout.statsBlockHeight - 10
            let targetCenterY = (targetTop + targetBottom) / 2
            let screenCenterY = canvasSize.height / 2
            let screenShiftY = max(screenCenterY - targetCenterY, 0)
            if screenShiftY > 0 {
                let vertical = cameraDistance * Double(screenShiftY / canvasSize.height) * 0.88
                let southEdge = MKMapPoint(x: rect.midX, y: rect.minY).coordinate
                padded.append(
                    FlythroughGeo.offset(southEdge, meters: vertical, bearingDegrees: 180)
                )
            }

            if progress < 0.22 {
                let activeInsets = layout.activeAreaInsets(canvasSize: canvasSize)
                let topMargin = cameraDistance * Double(activeInsets.top / canvasSize.height) * 0.42
                if topMargin > 1 {
                    let northEdge = MKMapPoint(x: rect.midX, y: rect.maxY).coordinate
                    padded.append(
                        FlythroughGeo.offset(northEdge, meters: topMargin, bearingDegrees: 0)
                    )
                }
            }
        }

        return padded
    }

    /// 카메라 look-at — GPS 지터가 줄어든 축 좌표 + HUD 보정(마커 위치와 분리).
    private static func flightLookAtCenter(
        route: FlythroughRoute,
        progress: Double,
        layout: FlythroughHUDLayout.Metrics,
        canvasSize: CGSize,
        cameraDistance: CLLocationDistance,
        isLandscape: Bool
    ) -> CLLocationCoordinate2D {
        let lookAt = route.cameraLookAtCoordinate(at: progress)
        let framing = flightFramingCoordinates(route: route, progress: progress)
        let routeSpan = routeNorthSouthSpanMeters(for: framing)

        if isLandscape {
            return FlythroughHUDLayout.landscapeLookAtCoordinate(
                lookAt,
                layout: layout,
                canvasSize: canvasSize,
                cameraDistance: cameraDistance,
                routeSpanMeters: routeSpan,
                clearProfileOverlap: progress >= 0.92
            )
        }

        return FlythroughHUDLayout.portraitActiveAreaLookAt(
            lookAt,
            layout: layout,
            canvasSize: canvasSize,
            cameraDistance: cameraDistance,
            routeSpanMeters: routeSpan
        )
    }

    /// 비행 고정 pitch — 탑뷰(0°)보다 기울여 지형·고도감을 살림. 진행 중 변화는 줌 울렁 유발.
    private static func flightPitch(isLandscape: Bool) -> CGFloat {
        _ = isLandscape
        return 52
    }

    /// 프레임별 bbox 기반 거리를 진행률 곡선으로 평탄화 — 줌인·줌아웃 반복을 제거합니다.
    private static func stabilizedFlightDistances(
        progress: [Double],
        rawDistances: [CLLocationDistance],
        sampleCount: Int = 14
    ) -> [CLLocationDistance] {
        guard !progress.isEmpty, progress.count == rawDistances.count else { return rawDistances }

        var keyProgress: [Double] = []
        var keyDistances: [CLLocationDistance] = []
        keyProgress.reserveCapacity(sampleCount + 1)
        keyDistances.reserveCapacity(sampleCount + 1)

        for sample in 0...sampleCount {
            let target = Double(sample) / Double(sampleCount)
            keyProgress.append(target)
            let neighborhoodRadius = 1.0 / Double(sampleCount + 2)
            let neighborhood = zip(progress, rawDistances).filter {
                abs($0.0 - target) <= neighborhoodRadius
            }.map(\.1)
            let sampled = neighborhood.max()
                ?? interpolateRawDistance(progress: progress, distances: rawDistances, at: target)
            keyDistances.append(sampled)
        }

        for index in 1..<keyDistances.count {
            keyDistances[index] = max(keyDistances[index], keyDistances[index - 1])
        }

        var result = progress.map {
            interpolatePiecewiseSmooth(
                keys: keyProgress,
                values: keyDistances,
                at: $0
            )
        }

        for index in 1..<result.count {
            result[index] = max(result[index], result[index - 1])
        }
        return result
    }

    /// 초반 줌인 → 후반 점진적 줌아웃. `stabilizedFlightDistances` 이후 적용합니다.
    private static func progressScaledFlightDistances(
        progress: [Double],
        distances: [CLLocationDistance],
        isLandscape: Bool
    ) -> [CLLocationDistance] {
        _ = isLandscape
        guard !progress.isEmpty, progress.count == distances.count else { return distances }

        let startScale = 0.86
        let endScale = 1.0
        let absoluteMinimum: CLLocationDistance = 520

        var result = zip(progress, distances).map { item, distance in
            let t = easeInOutMild(min(max(item, 0), 1))
            let scale = startScale + (endScale - startScale) * t
            return max(distance * scale, absoluteMinimum)
        }

        for index in 1..<result.count {
            result[index] = max(result[index], result[index - 1])
        }
        return result
    }

    private static func interpolateRawDistance(
        progress: [Double],
        distances: [CLLocationDistance],
        at target: Double
    ) -> CLLocationDistance {
        guard let last = progress.indices.last else { return distances.first ?? 800 }
        if target <= progress[0] { return distances[0] }
        if target >= progress[last] { return distances[last] }
        for index in 0..<last {
            let p0 = progress[index]
            let p1 = progress[index + 1]
            guard target >= p0, target <= p1, p1 > p0 else { continue }
            let t = (target - p0) / (p1 - p0)
            return distances[index] + (distances[index + 1] - distances[index]) * t
        }
        return distances[last]
    }

    private static func interpolatePiecewiseSmooth(
        keys: [Double],
        values: [CLLocationDistance],
        at progress: Double
    ) -> CLLocationDistance {
        guard let firstKey = keys.first,
              let lastKey = keys.last,
              let firstValue = values.first,
              let lastValue = values.last else {
            return values.first ?? 800
        }
        if progress <= firstKey { return firstValue }
        if progress >= lastKey { return lastValue }

        for index in 0..<(keys.count - 1) {
            let start = keys[index]
            let end = keys[index + 1]
            guard progress >= start, progress <= end, end > start else { continue }
            let t = (progress - start) / (end - start)
            let smooth = t * t * (3 - 2 * t)
            return values[index] + (values[index + 1] - values[index]) * smooth
        }
        return lastValue
    }

    /// 카메라 중심(look-at)을 프레임 간 이동평균으로 저역통과합니다.
    private static func smoothCenters(_ params: [CameraParameters], window: Int) -> [CameraParameters] {
        guard window > 0, params.count > 2 else { return params }
        var result = params
        for index in params.indices {
            let lower = max(0, index - window)
            let upper = min(params.count - 1, index + window)
            var latitude = 0.0
            var longitude = 0.0
            var count = 0.0
            for j in lower...upper {
                latitude += params[j].center.latitude
                longitude += params[j].center.longitude
                count += 1
            }
            result[index].center = CLLocationCoordinate2D(
                latitude: latitude / count,
                longitude: longitude / count
            )
        }
        return result
    }

    /// 카메라 거리를 프레임 간 스무딩합니다.
    private static func smoothDistances(_ params: [CameraParameters], window: Int) -> [CameraParameters] {
        guard window > 0, params.count > 2 else { return params }
        var result = params
        for index in params.indices {
            let lower = max(0, index - window)
            let upper = min(params.count - 1, index + window)
            var sum = 0.0
            var count = 0.0
            for j in lower...upper {
                sum += params[j].distance
                count += 1
            }
            result[index].distance = sum / count
        }
        return result
    }

    /// 경로 최장축 — 가장 멀리 떨어진 두 GPS 포인트.
    private struct RouteLongAxis {
        /// 좌하 대각 방향에 둘 끝(출발점에 가까운 쪽).
        let nearDiagonalEnd: CLLocationCoordinate2D
        /// 우상 대각 방향에 둘 끝.
        let farDiagonalEnd: CLLocationCoordinate2D

        var bearing: CLLocationDirection {
            FlythroughGeo.bearing(from: nearDiagonalEnd, to: farDiagonalEnd)
        }
    }

    /// 경로상 최장축 양 끝을 찾고, 출발점이 좌하 대각 쪽이 되도록 정렬합니다.
    private static func routeLongAxis(
        for coordinates: [CLLocationCoordinate2D],
        routeStart: CLLocationCoordinate2D
    ) -> RouteLongAxis? {
        guard let pair = farthestCoordinatePair(in: coordinates) else { return nil }

        if FlythroughGeo.distance(routeStart, pair.0) <= FlythroughGeo.distance(routeStart, pair.1) {
            return RouteLongAxis(nearDiagonalEnd: pair.0, farDiagonalEnd: pair.1)
        }
        return RouteLongAxis(nearDiagonalEnd: pair.1, farDiagonalEnd: pair.0)
    }

    /// 샘플 좌표에서 최장 거리 쌍을 구합니다.
    private static func farthestCoordinatePair(
        in coordinates: [CLLocationCoordinate2D]
    ) -> (CLLocationCoordinate2D, CLLocationCoordinate2D)? {
        let samples = sampledCoordinates(coordinates, maxCount: 96)
        guard samples.count >= 2 else { return nil }

        var maxDistance: CLLocationDistance = 0
        var endpointA = samples[0]
        var endpointB = samples[1]
        for index in samples.indices {
            for other in (index + 1)..<samples.count {
                let distance = FlythroughGeo.distance(samples[index], samples[other])
                if distance > maxDistance {
                    maxDistance = distance
                    endpointA = samples[index]
                    endpointB = samples[other]
                }
            }
        }
        guard maxDistance > 80 else { return nil }
        return (endpointA, endpointB)
    }

    /// 장축 near→far bearing을 화면 대각(좌하→우상) 각도에 맞추는 탑뷰 heading.
    /// `bearing − heading = screenDiagonalAngle` → `heading = bearing − screenDiagonalAngle`
    private static func topViewHeading(
        longAxis: RouteLongAxis,
        screenDiagonalAngleFromUp: CLLocationDirection
    ) -> CLLocationDirection {
        (longAxis.bearing - screenDiagonalAngleFromUp + 360).truncatingRemainder(dividingBy: 360)
    }

    /// 경로 장축 방위 — 비행·프레이밍용.
    private static func dominantRouteHeading(_ coordinates: [CLLocationCoordinate2D]) -> CLLocationDirection {
        guard coordinates.count >= 2,
              let start = coordinates.first,
              let axis = routeLongAxis(for: coordinates, routeStart: start) else {
            guard let first = coordinates.first, let last = coordinates.last else { return 0 }
            return netDisplacementBearing(from: first, to: last)
        }
        return axis.bearing
    }

    private static func sampledCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        maxCount: Int
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > maxCount, maxCount >= 2 else { return coordinates }
        var samples: [CLLocationCoordinate2D] = []
        samples.reserveCapacity(maxCount)
        let step = Double(coordinates.count - 1) / Double(maxCount - 1)
        for index in 0..<maxCount {
            samples.append(coordinates[Int((Double(index) * step).rounded())])
        }
        return samples
    }

    private static func netDisplacementBearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> CLLocationDirection {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: - Camera parameters

    private struct CameraParameters {
        var center: CLLocationCoordinate2D
        var distance: CLLocationDistance
        var pitch: CGFloat
        var heading: CLLocationDirection

        func makeCamera() -> MKMapCamera {
            MKMapCamera(
                lookingAtCenter: center,
                fromDistance: distance,
                pitch: pitch,
                heading: heading
            )
        }
    }

    /// 인트로 줌 — 전경(탑뷰)에서 비행 시작 카메라(시작점)로 전환합니다.
    private static func introZoomParameters(
        from establishing: CameraParameters,
        to flightStart: CameraParameters,
        zoomProgress: Double,
        configuration: FlythroughVideoConfiguration
    ) -> CameraParameters {
        let zoomT = easeInOut(min(max(zoomProgress, 0), 1))
        if configuration.orientation == .landscape {
            let panT = easeInOut(pow(zoomT, 1.6))
            return CameraParameters(
                center: FlythroughGeo.interpolate(
                    from: establishing.center,
                    to: flightStart.center,
                    fraction: panT
                ),
                distance: establishing.distance + (flightStart.distance - establishing.distance) * zoomT,
                pitch: establishing.pitch + (flightStart.pitch - establishing.pitch) * CGFloat(zoomT),
                heading: interpolateHeading(
                    from: establishing.heading,
                    to: flightStart.heading,
                    t: panT
                )
            )
        }
        return interpolate(from: establishing, to: flightStart, t: zoomT)
    }

    /// 아웃트로 줌 — 거리·중심 먼저, pitch·heading은 늦게·완만하게 탑뷰로(급격한 기울기 변화 방지).
    private static func outroTransitionParameters(
        from flightEnd: CameraParameters,
        to establishing: CameraParameters,
        easedProgress t: Double,
        isLandscape: Bool
    ) -> CameraParameters {
        let centerT = isLandscape
            ? easeInOut(pow(t, 1.55))
            : easeInOut(pow(t, 1.12))
        let distanceT = t

        // pitch·heading은 홀드 직후 t=0에서도 flightEnd와 동일. 이후에만 완만히 탑뷰로.
        let pitchLead = 0.08
        let pitchT: Double
        if t <= pitchLead {
            pitchT = 0
        } else {
            pitchT = easeInOut(pow((t - pitchLead) / (1 - pitchLead), isLandscape ? 3.8 : 3.2))
        }

        let headingLead = 0.06
        let headingT: Double
        if t <= headingLead {
            headingT = 0
        } else {
            headingT = easeInOut(pow((t - headingLead) / (1 - headingLead), isLandscape ? 2.6 : 2.8))
        }

        return CameraParameters(
            center: FlythroughGeo.interpolate(
                from: flightEnd.center,
                to: establishing.center,
                fraction: centerT
            ),
            distance: flightEnd.distance + (establishing.distance - flightEnd.distance) * distanceT,
            pitch: flightEnd.pitch + (establishing.pitch - flightEnd.pitch) * CGFloat(pitchT),
            heading: interpolateHeading(
                from: flightEnd.heading,
                to: establishing.heading,
                t: headingT
            )
        )
    }

    private static func flightParameters(
        route: FlythroughRoute,
        progress: Double,
        configuration: FlythroughVideoConfiguration,
        canvasSize: CGSize,
        heading: CLLocationDirection
    ) -> CameraParameters {
        let layout = FlythroughHUDLayout.metrics(
            canvasSize: canvasSize,
            orientation: configuration.orientation
        )
        let isLandscape = configuration.orientation == .landscape
        let pitch = flightPitch(isLandscape: isLandscape)
        let distance = flightFramingDistance(
            route: route,
            progress: progress,
            configuration: configuration,
            canvasSize: canvasSize,
            layout: layout,
            pitch: pitch
        )

        let center = flightLookAtCenter(
            route: route,
            progress: progress,
            layout: layout,
            canvasSize: canvasSize,
            cameraDistance: distance,
            isLandscape: isLandscape
        )

        return CameraParameters(
            center: center,
            distance: distance,
            pitch: pitch,
            heading: heading
        )
    }

    /// 진행률까지의 이동 경로가 화면에 들어오도록 하는 카메라 거리.
    private static func flightFramingDistance(
        route: FlythroughRoute,
        progress: Double,
        configuration: FlythroughVideoConfiguration,
        canvasSize: CGSize,
        layout: FlythroughHUDLayout.Metrics,
        pitch: CGFloat
    ) -> CLLocationDistance {
        let isLandscape = configuration.orientation == .landscape
        let baseFraming = flightFramingCoordinates(route: route, progress: progress)

        let fillFraction: CGFloat = 0.58
        let distanceBoost = 1.12
        let headMarginBoost: Double = 1.08
        let startMarginBoost: Double = progress < 0.15 ? 1.06 : 1.0
        let flightInsets: UIEdgeInsets? = isLandscape
            ? layout.landscapeFlightMapInsets(canvasSize: canvasSize)
            : layout.portraitFlightMapInsets(canvasSize: canvasSize)

        let minDistance: CLLocationDistance = 680

        guard baseFraming.count >= 1 else {
            return minDistance
        }

        let baseDistance = cameraDistance(
            for: baseFraming,
            canvasSize: canvasSize,
            layout: layout,
            pitch: pitch,
            routeFillFraction: fillFraction,
            distanceBoost: distanceBoost * headMarginBoost * startMarginBoost,
            minimumDistance: minDistance,
            hudInsetsOverride: flightInsets
        )
        let paddedFraming = flightFramingHUDPadding(
            route: route,
            coordinates: baseFraming,
            progress: progress,
            layout: layout,
            canvasSize: canvasSize,
            cameraDistance: baseDistance,
            isLandscape: isLandscape
        )
        let paddedDistance = cameraDistance(
            for: paddedFraming,
            canvasSize: canvasSize,
            layout: layout,
            pitch: pitch,
            routeFillFraction: fillFraction,
            distanceBoost: distanceBoost * headMarginBoost * startMarginBoost,
            minimumDistance: minDistance,
            hudInsetsOverride: flightInsets
        )
        let fitDistance = max(baseDistance, paddedDistance)
        return fitDistance
    }

    private static func establishingParameters(
        route: FlythroughRoute,
        canvasSize: CGSize,
        configuration: FlythroughVideoConfiguration
    ) -> CameraParameters {
        if configuration.orientation == .landscape {
            return landscapeEstablishingParameters(
                route: route,
                canvasSize: canvasSize
            )
        }
        return portraitEstablishingParameters(
            route: route,
            canvasSize: canvasSize
        )
    }

    /// 가로 탑뷰 — 가용 영역 대각(좌하→우상)에 장축 정렬.
    private static func landscapeEstablishingParameters(
        route: FlythroughRoute,
        canvasSize: CGSize
    ) -> CameraParameters {
        guard canvasSize.width > 0, canvasSize.height > 0, !route.coordinates.isEmpty else {
            return fallbackEstablishingCamera(route: route)
        }
        let base = sharedEstablishingBase(route: route, canvasSize: canvasSize)
        let layout = FlythroughHUDLayout.metrics(
            canvasSize: canvasSize,
            orientation: .landscape
        )
        let axisAngle = layout.landscapeFinalRouteDiagonalAngleFromScreenUp(canvasSize: canvasSize)
        let establishingHeading = establishingHeading(
            longAxis: base.longAxis,
            routeStart: base.routeStart,
            routeEnd: base.coordinates.last ?? base.routeStart,
            axisAngleFromScreenUp: axisAngle
        )
        let framing = establishingLookAtAndDistance(
            base: base,
            establishingHeading: establishingHeading,
            layout: layout,
            canvasSize: canvasSize,
            minimumDistance: 640
        )
        return CameraParameters(
            center: framing.center,
            distance: framing.distance,
            pitch: 0,
            heading: establishingHeading
        )
    }

    /// 세로 탑뷰 — 첫 번째 붉은 영역에 전체 경로, 장축은 두 번째 영역 각도(완만한 대각).
    private static func portraitEstablishingParameters(
        route: FlythroughRoute,
        canvasSize: CGSize
    ) -> CameraParameters {
        guard canvasSize.width > 0, canvasSize.height > 0, !route.coordinates.isEmpty else {
            return fallbackEstablishingCamera(route: route)
        }
        let base = sharedEstablishingBase(route: route, canvasSize: canvasSize)
        let layout = FlythroughHUDLayout.metrics(
            canvasSize: canvasSize,
            orientation: .portrait
        )
        let axisAngle = layout.portraitFinalRouteAxisAngleFromScreenUp(canvasSize: canvasSize)
        let establishingHeading = establishingHeading(
            longAxis: base.longAxis,
            routeStart: base.routeStart,
            routeEnd: base.coordinates.last ?? base.routeStart,
            axisAngleFromScreenUp: axisAngle
        )
        let framing = establishingLookAtAndDistance(
            base: base,
            establishingHeading: establishingHeading,
            layout: layout,
            canvasSize: canvasSize,
            minimumDistance: 720
        )
        return CameraParameters(
            center: framing.center,
            distance: framing.distance,
            pitch: 0,
            heading: establishingHeading
        )
    }

    private static func fallbackEstablishingCamera(route: FlythroughRoute) -> CameraParameters {
        CameraParameters(
            center: route.coordinates.first ?? CLLocationCoordinate2D(),
            distance: 1100,
            pitch: 0,
            heading: 0
        )
    }

    private struct EstablishingBase {
        let coordinates: [CLLocationCoordinate2D]
        let framingCoordinates: [CLLocationCoordinate2D]
        let routeStart: CLLocationCoordinate2D
        let longAxis: RouteLongAxis?
        let geographicCenter: CLLocationCoordinate2D
        let routeSpanMeters: CLLocationDistance
    }

    private static func sharedEstablishingBase(
        route: FlythroughRoute,
        canvasSize: CGSize
    ) -> EstablishingBase {
        let coordinates = route.coordinates
        let framingCoordinates = route.finalRouteFramingCoordinates(
            labelSideOffsetMeters: canvasSize.width > canvasSize.height ? 52 : 64
        )
        let routeStart = coordinates.first ?? CLLocationCoordinate2D()
        let resolvedLongAxis = routeLongAxis(for: coordinates, routeStart: routeStart)
        let framingRect = HikingMapRegion.routeBoundingMapRect(for: framingCoordinates)
        let geographicCenter: CLLocationCoordinate2D
        if let resolvedLongAxis {
            geographicCenter = FlythroughGeo.interpolate(
                from: resolvedLongAxis.nearDiagonalEnd,
                to: resolvedLongAxis.farDiagonalEnd,
                fraction: 0.5
            )
        } else {
            geographicCenter = MKMapPoint(x: framingRect.midX, y: framingRect.midY).coordinate
        }
        let routeSpanMeters = routeNorthSouthSpanMeters(for: framingCoordinates)
        return EstablishingBase(
            coordinates: coordinates,
            framingCoordinates: framingCoordinates,
            routeStart: routeStart,
            longAxis: resolvedLongAxis,
            geographicCenter: geographicCenter,
            routeSpanMeters: routeSpanMeters
        )
    }

    private static func establishingHeading(
        longAxis: RouteLongAxis?,
        routeStart: CLLocationCoordinate2D,
        routeEnd: CLLocationCoordinate2D,
        axisAngleFromScreenUp: CLLocationDirection
    ) -> CLLocationDirection {
        if let longAxis {
            return topViewHeading(
                longAxis: longAxis,
                screenDiagonalAngleFromUp: axisAngleFromScreenUp
            )
        }
        return topViewHeading(
            longAxis: RouteLongAxis(
                nearDiagonalEnd: routeStart,
                farDiagonalEnd: routeEnd
            ),
            screenDiagonalAngleFromUp: axisAngleFromScreenUp
        )
    }

    private static func establishingCameraDistance(
        framingCoordinates: [CLLocationCoordinate2D],
        geographicCenter: CLLocationCoordinate2D,
        establishingHeading: CLLocationDirection,
        canvasSize: CGSize,
        layout: FlythroughHUDLayout.Metrics,
        routeFillFraction: CGFloat,
        distanceBoost: Double,
        minimumDistance: CLLocationDistance,
        fitInsets: UIEdgeInsets
    ) -> CLLocationDistance {
        let paddedFraming = paddedEstablishingFramingCoordinates(
            framingCoordinates,
            heading: establishingHeading,
            center: geographicCenter
        )
        let framingForDistance = FlythroughGeo.rotateCoordinates(
            paddedFraming,
            around: geographicCenter,
            byDegrees: -establishingHeading
        )
        return cameraDistance(
            for: framingForDistance,
            canvasSize: canvasSize,
            layout: layout,
            pitch: 0,
            routeFillFraction: routeFillFraction,
            distanceBoost: distanceBoost,
            minimumDistance: minimumDistance,
            hudInsetsOverride: fitInsets
        )
    }

    /// look-at HUD 보정으로 화면 밖으로 밀린 만큼 줌아웃합니다.
    private static func establishingFinalDistance(
        preliminaryDistance: CLLocationDistance,
        geographicCenter: CLLocationCoordinate2D,
        lookAtCenter: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        var distance = preliminaryDistance * FlythroughPipelineTuning.finalRouteDistanceSafetyMultiplier
        let shift = FlythroughGeo.distance(geographicCenter, lookAtCenter)
        guard shift > 1, distance > 0 else { return distance }
        let shiftRatio = shift / distance
        distance *= 1.0 + min(shiftRatio * 0.9, 0.24)
        return distance
    }

    private struct ScreenAlignedBBox {
        let center: CLLocationCoordinate2D
        let widthMeters: CLLocationDistance
        let heightMeters: CLLocationDistance
    }

    /// 카메라 heading 기준 화면 좌표계에서 경로(라벨 패딩 포함)의 바운딩 박스를 구합니다.
    private static func establishingScreenAlignedBBox(
        framingCoordinates: [CLLocationCoordinate2D],
        heading: CLLocationDirection
    ) -> ScreenAlignedBBox? {
        guard framingCoordinates.count >= 2 else { return nil }

        var latitude = 0.0
        var longitude = 0.0
        for coordinate in framingCoordinates {
            latitude += coordinate.latitude
            longitude += coordinate.longitude
        }
        let count = Double(framingCoordinates.count)
        let centroid = CLLocationCoordinate2D(
            latitude: latitude / count,
            longitude: longitude / count
        )

        let aligned = FlythroughGeo.rotateCoordinates(
            framingCoordinates,
            around: centroid,
            byDegrees: -heading
        )
        let rect = HikingMapRegion.routeBoundingMapRect(for: aligned)
        guard !rect.isNull else { return nil }

        let alignedCenter = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
        let metersPerPoint = MKMapPointsPerMeterAtLatitude(alignedCenter.latitude)
        let worldCenter = FlythroughGeo.rotateCoordinates(
            [alignedCenter],
            around: centroid,
            byDegrees: heading
        ).first ?? alignedCenter

        return ScreenAlignedBBox(
            center: worldCenter,
            widthMeters: rect.width / metersPerPoint,
            heightMeters: rect.height / metersPerPoint
        )
    }

    /// 바운딩 박스가 가용 영역(`finalRouteMapInsets`) 안에 좌우·상하 여백이 균등하도록 들어가는 카메라 거리.
    private static func establishingDistanceFittingBBox(
        bbox: ScreenAlignedBBox,
        canvasSize: CGSize,
        layout: FlythroughHUDLayout.Metrics,
        fillFraction: CGFloat,
        minimumDistance: CLLocationDistance
    ) -> CLLocationDistance {
        let insets = layout.finalRouteMapInsets(canvasSize: canvasSize)
        let usableWidth = max(canvasSize.width - insets.left - insets.right, 1)
        let usableHeight = max(canvasSize.height - insets.top - insets.bottom, 1)
        let fill = min(max(fillFraction, 0.55), 0.96)
        let factor = FlythroughHUDLayout.topViewMetersPerCanvasHeightFactor
        let canvasHeight = max(Double(canvasSize.height), 1)

        let distanceForHeight = bbox.heightMeters * canvasHeight
            / (factor * Double(usableHeight) * Double(fill))
        let distanceForWidth = bbox.widthMeters * canvasHeight
            / (factor * Double(usableWidth) * Double(fill))

        return max(distanceForHeight, distanceForWidth, minimumDistance) * 1.03
    }

    /// 최종 전경 — 경로 화면 바운딩 박스를 가용 영역 정중앙에 맞추고 좌우·상하 여백을 균등하게 맞춥니다.
    private static func establishingLookAtAndDistance(
        base: EstablishingBase,
        establishingHeading: CLLocationDirection,
        layout: FlythroughHUDLayout.Metrics,
        canvasSize: CGSize,
        minimumDistance: CLLocationDistance
    ) -> (center: CLLocationCoordinate2D, distance: CLLocationDistance) {
        guard let bbox = establishingScreenAlignedBBox(
            framingCoordinates: base.framingCoordinates,
            heading: establishingHeading
        ) else {
            return (base.geographicCenter, minimumDistance)
        }

        var lookAt = bbox.center
        var distance = establishingDistanceFittingBBox(
            bbox: bbox,
            canvasSize: canvasSize,
            layout: layout,
            fillFraction: 0.92,
            minimumDistance: minimumDistance
        )

        for _ in 0..<4 {
            let screenFrame = establishingScreenFrame(
                framingCoordinates: base.framingCoordinates,
                lookAt: lookAt,
                distance: distance,
                heading: establishingHeading,
                layout: layout,
                canvasSize: canvasSize
            )
            lookAt = balancingLookAt(
                lookAt: lookAt,
                screenFrame: screenFrame,
                distance: distance,
                heading: establishingHeading,
                canvasSize: canvasSize
            )
            distance = fittingDistance(
                screenFrame: establishingScreenFrame(
                    framingCoordinates: base.framingCoordinates,
                    lookAt: lookAt,
                    distance: distance,
                    heading: establishingHeading,
                    layout: layout,
                    canvasSize: canvasSize
                ),
                distance: distance,
                fillFraction: 0.92
            )
        }

        return (lookAt, distance)
    }

    private struct EstablishingScreenFrame {
        let minX: CGFloat
        let maxX: CGFloat
        let minY: CGFloat
        let maxY: CGFloat
        let usableLeft: CGFloat
        let usableRight: CGFloat
        let usableTop: CGFloat
        let usableBottom: CGFloat

        var bboxWidth: CGFloat { max(0, maxX - minX) }
        var bboxHeight: CGFloat { max(0, maxY - minY) }
        var usableWidth: CGFloat { max(0, usableRight - usableLeft) }
        var usableHeight: CGFloat { max(0, usableBottom - usableTop) }
        var leftMargin: CGFloat { minX - usableLeft }
        var rightMargin: CGFloat { usableRight - maxX }
        var topMargin: CGFloat { minY - usableTop }
        var bottomMargin: CGFloat { usableBottom - maxY }
    }

    private static func establishingScreenFrame(
        framingCoordinates: [CLLocationCoordinate2D],
        lookAt: CLLocationCoordinate2D,
        distance: CLLocationDistance,
        heading: CLLocationDirection,
        layout: FlythroughHUDLayout.Metrics,
        canvasSize: CGSize
    ) -> EstablishingScreenFrame? {
        let insets = layout.finalRouteMapInsets(canvasSize: canvasSize)
        let screenPoints = framingCoordinates.map {
            FlythroughHUDLayout.topViewScreenPoint(
                for: $0,
                lookAt: lookAt,
                cameraDistance: distance,
                cameraHeading: heading,
                canvasSize: canvasSize
            )
        }
        guard let minX = screenPoints.map(\.x).min(),
              let maxX = screenPoints.map(\.x).max(),
              let minY = screenPoints.map(\.y).min(),
              let maxY = screenPoints.map(\.y).max() else {
            return nil
        }
        return EstablishingScreenFrame(
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY,
            usableLeft: insets.left,
            usableRight: canvasSize.width - insets.right,
            usableTop: insets.top,
            usableBottom: canvasSize.height - insets.bottom
        )
    }

    /// 좌·우·상·하 여백 차이를 줄이도록 look-at을 보정합니다.
    private static func balancingLookAt(
        lookAt: CLLocationCoordinate2D,
        screenFrame: EstablishingScreenFrame?,
        distance: CLLocationDistance,
        heading: CLLocationDirection,
        canvasSize: CGSize
    ) -> CLLocationCoordinate2D {
        guard let frame = screenFrame else { return lookAt }
        let metersPerPoint = FlythroughHUDLayout.topViewMetersPerPoint(
            cameraDistance: distance,
            canvasHeight: canvasSize.height
        )
        guard metersPerPoint > 0 else { return lookAt }

        var result = lookAt
        let horizontalShift = (frame.leftMargin - frame.rightMargin) / 2
        if abs(horizontalShift) > 0.25 {
            result = FlythroughGeo.offset(
                result,
                meters: Double(abs(horizontalShift)) * metersPerPoint,
                bearingDegrees: FlythroughHUDLayout.screenRelativeBearing(
                    cameraHeading: heading,
                    screenBearing: horizontalShift < 0 ? 270 : 90
                )
            )
        }

        let verticalShift = (frame.topMargin - frame.bottomMargin) / 2
        if abs(verticalShift) > 0.25 {
            result = FlythroughGeo.offset(
                result,
                meters: Double(abs(verticalShift)) * metersPerPoint,
                bearingDegrees: FlythroughHUDLayout.screenRelativeBearing(
                    cameraHeading: heading,
                    screenBearing: verticalShift > 0 ? 180 : 0
                )
            )
        }
        return result
    }

    /// 화면 바운딩 박스가 가용 영역을 넘치면 거리를 늘려 균등 여백을 확보합니다.
    private static func fittingDistance(
        screenFrame: EstablishingScreenFrame?,
        distance: CLLocationDistance,
        fillFraction: CGFloat
    ) -> CLLocationDistance {
        guard let frame = screenFrame else { return distance }
        let fill = min(max(fillFraction, 0.70), 0.96)
        guard frame.usableWidth > 0, frame.usableHeight > 0 else { return distance }

        var next = distance
        let targetWidth = frame.usableWidth * fill
        let targetHeight = frame.usableHeight * fill
        if frame.bboxWidth > targetWidth {
            next *= Double(frame.bboxWidth / targetWidth)
        }
        if frame.bboxHeight > targetHeight {
            next *= Double(frame.bboxHeight / targetHeight)
        }
        return max(next, distance)
    }

    /// km 라벨 버블이 바운딩 박스 위·아래로 튀어나오는 여유(미터).
    private static func paddedEstablishingFramingCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        heading: CLLocationDirection,
        center: CLLocationCoordinate2D
    ) -> [CLLocationCoordinate2D] {
        let pad = FlythroughPipelineTuning.finalRouteMarkerVerticalPaddingMeters
        guard pad > 0, coordinates.count >= 2 else { return coordinates }
        var result = coordinates
        result.reserveCapacity(coordinates.count + 4)
        result.append(FlythroughGeo.offset(center, meters: pad, bearingDegrees: heading))
        result.append(FlythroughGeo.offset(center, meters: pad, bearingDegrees: (heading + 180).truncatingRemainder(dividingBy: 360)))
        return result
    }

    /// 비행 heading — 가로: 장축을 화면 가로에 / 세로: 붉은 영역 장축 각도(완만한 대각).
    private static func flightCameraHeading(
        routeHeading: CLLocationDirection,
        longAxis: RouteLongAxis?,
        layout: FlythroughHUDLayout.Metrics,
        canvasSize: CGSize,
        isLandscape: Bool
    ) -> CLLocationDirection {
        if isLandscape {
            return (routeHeading - 90 + 360).truncatingRemainder(dividingBy: 360)
        }
        let axisAngle = layout.portraitFinalRouteAxisAngleFromScreenUp(canvasSize: canvasSize)
        if let longAxis {
            return topViewHeading(
                longAxis: longAxis,
                screenDiagonalAngleFromUp: axisAngle
            )
        }
        return (routeHeading - axisAngle + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func routeNorthSouthSpanMeters(for coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
        let rect = HikingMapRegion.routeBoundingMapRect(for: coordinates)
        guard !rect.isNull, let first = coordinates.first else { return 0 }
        return rect.height / MKMapPointsPerMeterAtLatitude(first.latitude)
    }

    /// 경로 좌표 배열이 HUD 안에 들어오도록 하는 카메라 거리(미터).
    private static func cameraDistance(
        for coordinates: [CLLocationCoordinate2D],
        canvasSize: CGSize,
        layout: FlythroughHUDLayout.Metrics,
        pitch: CGFloat,
        routeFillFraction: CGFloat,
        distanceBoost: Double,
        minimumDistance: CLLocationDistance,
        extraBottomInset: CGFloat = 0,
        hudInsetsOverride: UIEdgeInsets? = nil
    ) -> CLLocationDistance {
        var hudInsets = hudInsetsOverride ?? layout.mapInsets
        if hudInsetsOverride == nil {
            hudInsets.bottom += extraBottomInset
        }
        let usableWidth = max(canvasSize.width - hudInsets.left - hudInsets.right, 1)
        let usableHeight = max(canvasSize.height - hudInsets.top - hudInsets.bottom, 1)
        let effectiveAspect = usableWidth / usableHeight

        let visibleRect = HikingMapRegion.visibleMapRect(
            for: coordinates,
            routeFillFraction: routeFillFraction,
            fittingAspectRatio: effectiveAspect
        )
        guard !visibleRect.isNull else { return minimumDistance }

        let center = MKMapPoint(x: visibleRect.midX, y: visibleRect.midY).coordinate
        let metersPerPoint = MKMapPointsPerMeterAtLatitude(center.latitude)
        let spanNorthSouth = visibleRect.height / metersPerPoint
        let spanEastWest = visibleRect.width / metersPerPoint

        let pitchRadians = Double(pitch) * .pi / 180
        let cosPitch = max(cos(pitchRadians), 0.15)
        let verticalFOV = 50.0 * .pi / 180
        let horizontalFOV = 2 * atan(tan(verticalFOV / 2) * Double(effectiveAspect))

        let distanceForHeight = (spanNorthSouth / 2) / tan(verticalFOV / 2) / cosPitch
        let distanceForWidth = (spanEastWest / 2) / tan(horizontalFOV / 2) / cosPitch
        let distance = max(distanceForHeight, distanceForWidth) * distanceBoost

        return max(distance, minimumDistance)
    }

    private static func interpolate(
        from: CameraParameters,
        to: CameraParameters,
        t: Double
    ) -> CameraParameters {
        CameraParameters(
            center: FlythroughGeo.interpolate(from: from.center, to: to.center, fraction: t),
            distance: from.distance + (to.distance - from.distance) * t,
            pitch: from.pitch + (to.pitch - from.pitch) * CGFloat(t),
            heading: interpolateHeading(from: from.heading, to: to.heading, t: t)
        )
    }

    private static func interpolateHeading(
        from: CLLocationDirection,
        to: CLLocationDirection,
        t: Double
    ) -> CLLocationDirection {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return (from + delta * t + 360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: - Easing

    private static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    private static func easeInOutMild(_ t: Double) -> Double {
        let smooth = t * t * (3 - 2 * t)
        return t * 0.7 + smooth * 0.3
    }
}

#endif
