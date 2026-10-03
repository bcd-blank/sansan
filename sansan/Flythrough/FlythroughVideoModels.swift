//
//  FlythroughVideoModels.swift
//  sansan
//
//  Relive 스타일 3D 경로 영상 — 입력 데이터 준비 모델과 렌더 설정.
//  튜닝: `FlythroughQuality` · `FlythroughPipelineTunable`
//

#if os(iOS)

import CoreLocation
import Foundation
import MapKit
import UIKit

/// 영상 화면 방향.
enum FlythroughOrientation: String, CaseIterable, Identifiable {
    case portrait
    case landscape

    var id: String { rawValue }
    var label: String { self == .portrait ? "세로" : "가로" }
}

/// 영상 타이틀 결정 방식.
enum FlythroughTitleSource: String, CaseIterable, Identifiable {
    case autoPlaceName
    case recordTitle

    var id: String { rawValue }
    var label: String { self == .autoPlaceName ? "지명 자동검색" : "타이틀 반영" }
}

/// 지도 표시 방식.
enum FlythroughMapStyle: String, CaseIterable, Identifiable {
    case satellite
    case standard

    var id: String { rawValue }
    var label: String { self == .satellite ? "위성" : "표준" }
}

/// 3D 경로 영상 화질·속도 프리셋.
enum FlythroughQuality: String, CaseIterable, Identifiable {
    case fast
    case balanced
    case high

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fast: return "빠르게"
        case .balanced: return "균형"
        case .high: return "고화질"
        }
    }

    var settingsHint: String {
        switch self {
        case .fast: return "18fps · HD(720p) · 짧은 대기"
        case .balanced: return "24fps · FHD(1080p) · 경로 갱신 최적화"
        case .high: return "30fps · FHD(1080p) · 매 프레임 경로"
        }
    }

    var framesPerSecond: Int {
        switch self {
        case .fast: return 18
        case .balanced: return 24
        case .high: return 30
        }
    }

    /// 캔버스 포인트(세로 360×640 · 가로 640×360) 기준 출력 배율.
    /// fast ×2 = 720×1280(HD), balanced·high ×3 = 1080×1920 / 1920×1080(FHD).
    func renderScale(for orientation: FlythroughOrientation) -> CGFloat {
        switch self {
        case .fast: return 2.0
        case .balanced, .high: return 3.0
        }
    }

    /// 타일·GPU 대기 시간 배율. 낮을수록 빠릅니다.
    var timingScale: Double {
        switch self {
        case .fast: return 0.45
        case .balanced: return 0.62
        case .high: return 1.0
        }
    }

    var gpuDrainFullMilliseconds: Int {
        switch self {
        case .fast: return 10
        case .balanced: return 20
        case .high: return 48
        }
    }

    var gpuDrainLightMilliseconds: Int {
        switch self {
        case .fast: return 3
        case .balanced: return 6
        case .high: return 18
        }
    }

    /// 비행 구간 지도 경로선 갱신 단계 수 — 높을수록 부드럽지만 느립니다.
    var routeLineQuantizationSteps: Int {
        switch self {
        case .fast: return 36
        case .balanced: return 120
        case .high: return 240
        }
    }

    /// 활성 꼬리 그라데이션 세그먼트 수 — 적을수록 지도 오버레이 부담이 줄습니다.
    var routeGradientSegmentCount: Int {
        switch self {
        case .fast: return 6
        case .balanced: return 8
        case .high: return 16
        }
    }

    /// 비인트로 구간 지도 캡처 간격 (비행은 `FlythroughPipelineInvariant.flightCapturesMapEveryFrame`).
    var mapRenderStride: Int {
        switch self {
        case .fast: return 2
        case .balanced: return 2
        case .high: return 1
        }
    }
}

/// 영상 인코딩·렌더 해상도/프레임 설정.
struct FlythroughVideoConfiguration {
    /// 화질 프리셋(프레임률·해상도·대기 시간).
    var quality: FlythroughQuality = .balanced
    /// 초당 프레임 수. `quality` 적용 시 덮어씁니다.
    var framesPerSecond: Int = 24
    /// 본 비행(경로 따라가기) 길이(초).
    var flightDuration: TimeInterval = 18
    /// 인트로(중앙 타이틀 → 페이드아웃·시작점 줌인) 길이(초). 0이면 비행부터 시작합니다.
    var introDuration: TimeInterval = 4
    /// 아웃트로 — 줌아웃 전환 길이(초).
    var outroTransitionDuration: TimeInterval = 3
    /// 아웃트로 — 전체 경로 고정 노출 길이(초).
    var outroHoldDuration: TimeInterval = 12
    /// 아웃트로 총 길이(초).
    var outroDuration: TimeInterval {
        outroTransitionDuration + outroHoldDuration
    }
    /// 아웃트로 내 전환 구간 비율(오버레이 페이드용).
    var outroTransitionFraction: Double {
        guard outroDuration > 0 else { return 0.25 }
        return outroTransitionDuration / outroDuration
    }
    /// 3D 카메라 기울기(도). 비행은 `flightPitch`에서 별도 적용(고정 각도).
    var cameraPitch: CGFloat = 50
    /// 본 비행 카메라 시점 거리(미터). 멀수록 넓은 시야·완만한 앵글 변화.
    var flightCameraDistance: CLLocationDistance = 6000
    /// 화면 방향.
    var orientation: FlythroughOrientation = .portrait
    /// 지도 스타일(기본: 위성).
    var mapStyle: FlythroughMapStyle = .satellite
    /// 경로 위 사진 썸네일 팝업 표시.
    var showsPhotoMarkers: Bool = true
    /// 경로 위 1km 단위 거리 라벨 표시.
    var showsDistanceMarkers: Bool = false

    var totalDuration: TimeInterval {
        introDuration + flightDuration + outroDuration
    }

    /// 출력 해상도 배율(포인트 × 배율 = 픽셀). 낮을수록 빠르고 용량도 작아집니다.
    func renderScale(for orientation: FlythroughOrientation) -> CGFloat {
        quality.renderScale(for: orientation)
    }

    var timingScale: Double { quality.timingScale }

    var mapRenderStride: Int { quality.mapRenderStride }

    var routeLineQuantizationSteps: Int { quality.routeLineQuantizationSteps }

    var routeGradientSegmentCount: Int { quality.routeGradientSegmentCount }

    /// 영상 렌더 캔버스 크기(포인트) — 기기 화면과 무관한 고정 9:16 / 16:9.
    /// 출력 픽셀 = 캔버스 × renderScale (FHD 기준 ×3).
    var canvasSize: CGSize {
        switch orientation {
        case .portrait:
            return CGSize(width: 360, height: 640)
        case .landscape:
            return CGSize(width: 640, height: 360)
        }
    }

    /// 일반설정 값으로 구성합니다.
    static func fromPreferences() -> FlythroughVideoConfiguration {
        var configuration = FlythroughVideoConfiguration()
        configuration.applyPreferences()
        return configuration
    }

    mutating func applyPreferences() {
        quality = HikingFlythroughPreferences.quality
        framesPerSecond = quality.framesPerSecond
        orientation = HikingFlythroughPreferences.orientation
        mapStyle = HikingFlythroughPreferences.mapStyle
        showsPhotoMarkers = HikingFlythroughPreferences.showsPhotoMarkers
        showsDistanceMarkers = HikingFlythroughPreferences.showsDistanceMarkers
    }

    static let `default` = FlythroughVideoConfiguration()
}

/// 로딩 UI에 표시할 파이프라인 단계(영상 구조와 1:1).
enum FlythroughPipelineStep: Int, CaseIterable, Equatable {
    case analyzeRoute = 0
    case prepareMap
    case renderIntro
    case renderFlight
    case renderOutro
    case encodeVideo

    var title: String {
        switch self {
        case .analyzeRoute: return "경로 분석"
        case .prepareMap: return "3D 지도 준비"
        case .renderIntro: return "인트로"
        case .renderFlight: return "경로 따라가기"
        case .renderOutro: return "마무리"
        case .encodeVideo: return "영상 저장"
        }
    }

    var detail: String {
        switch self {
        case .analyzeRoute: return "기록 경로·통계·날씨를 불러오는 중…"
        case .prepareMap: return "위성 지도와 카메라를 준비하는 중…"
        case .renderIntro: return "산 이름과 시작 장면을 만드는 중…"
        case .renderFlight: return "기록을 따라 3D로 촬영하는 중…"
        case .renderOutro: return "전체 경로와 요약 화면을 만드는 중…"
        case .encodeVideo: return "프레임을 영상 파일로 저장하는 중…"
        }
    }

    var index: Int { rawValue + 1 }
}

/// 프레임 렌더 구간 — `FlythroughPhase`와 대응.
enum FlythroughRenderSegment: Equatable {
    case intro
    case flight
    case outro

    var pipelineStep: FlythroughPipelineStep {
        switch self {
        case .intro: return .renderIntro
        case .flight: return .renderFlight
        case .outro: return .renderOutro
        }
    }
}

enum FlythroughStepStatus: Equatable {
    case pending
    case active
    case completed
}

/// 영상 생성 진행 단계.
enum FlythroughProgressPhase: Equatable {
    case preparing(FlythroughPipelineStep, progress: Double)
    case rendering(fraction: Double, segment: FlythroughRenderSegment, segmentFraction: Double)
    case encoding(progress: Double)
    case finished
    case failed(String)

    var fraction: Double {
        switch self {
        case .preparing(let step, let progress):
            let clamped = min(max(progress, 0), 1)
            switch step {
            case .analyzeRoute: return 0.01 + clamped * 0.02
            case .prepareMap: return 0.03 + clamped * 0.02
            default: return 0.04
            }
        case .rendering(let f, _, _): return 0.05 + f * 0.85
        case .encoding(let progress): return 0.90 + min(max(progress, 0), 1) * 0.08
        case .finished: return 1
        case .failed: return 0
        }
    }

    var currentStep: FlythroughPipelineStep {
        switch self {
        case .preparing(let step, _): return step
        case .rendering(_, let segment, _): return segment.pipelineStep
        case .encoding, .finished: return .encodeVideo
        case .failed: return .analyzeRoute
        }
    }

    var message: String { currentStep.detail }

    func status(for step: FlythroughPipelineStep) -> FlythroughStepStatus {
        if case .finished = self {
            return .completed
        }
        if case .failed = self {
            return step == currentStep ? .active : (step.rawValue < currentStep.rawValue ? .completed : .pending)
        }
        let active = currentStep
        if step.rawValue < active.rawValue { return .completed }
        if step == active { return .active }
        return .pending
    }

    /// 단계별 진행률(0…1) — 로딩 목록의 개별 진행 바용.
    func progress(for step: FlythroughPipelineStep) -> Double {
        switch status(for: step) {
        case .completed:
            return 1
        case .pending:
            return 0
        case .active:
            switch self {
            case .preparing(let activeStep, let value) where activeStep == step:
                return min(max(value, 0), 1)
            case .rendering(_, _, let segmentFraction) where step == currentStep:
                return min(max(segmentFraction, 0), 1)
            case .encoding(let value) where step == .encodeVideo:
                return min(max(value, 0), 1)
            default:
                return 0
            }
        }
    }
}

/// 경로상의 한 위치를 시간·거리·고도와 함께 표현하는 보간 결과.
struct FlythroughRouteSample {
    var coordinate: CLLocationCoordinate2D
    /// 시작 지점 기준 누적 거리(미터).
    var distance: CLLocationDistance
    /// 해발 고도(미터).
    var altitude: Double
    /// 시작 시각 기준 경과 시간(초).
    var elapsed: TimeInterval
    /// 진행 방향(0=북, 시계방향 도).
    var heading: CLLocationDirection
}

/// 시작·종료 지점 라벨 배치 — km 마커와 동일한 캡슐+점 스타일.
struct RouteEndpointLabelPlacement {
    let kind: RouteEndpointLabelKind
    let coordinate: CLLocationCoordinate2D
    let placesLabelOnLeadingSide: Bool

    static func start(
        at coordinate: CLLocationCoordinate2D,
        placesLabelOnLeadingSide: Bool = false
    ) -> RouteEndpointLabelPlacement {
        RouteEndpointLabelPlacement(
            kind: .start,
            coordinate: coordinate,
            placesLabelOnLeadingSide: placesLabelOnLeadingSide
        )
    }

    static func end(
        at coordinate: CLLocationCoordinate2D,
        placesLabelOnLeadingSide: Bool = true
    ) -> RouteEndpointLabelPlacement {
        RouteEndpointLabelPlacement(
            kind: .end,
            coordinate: coordinate,
            placesLabelOnLeadingSide: placesLabelOnLeadingSide
        )
    }
}

/// 영상 지도에 그릴 경로 레이어 상태.
struct FlythroughRouteLineState {
    /// 진행된 경로.
    let traveled: [CLLocationCoordinate2D]
    /// 현재 이동 꼬리 — 머리(밝은 녹색) → 꼬리(짙은 녹색) 비선형 그라데이션 세그먼트.
    let activeTailSegments: [(coordinates: [CLLocationCoordinate2D], color: UIColor)]
    /// 현재 위치(겹치는 구간에서 진행 위치 표시).
    let head: CLLocationCoordinate2D?
    /// 머리 마커 불투명도(0~1).
    let headOpacity: CGFloat
    /// 시작 지점 라벨.
    let startEndpointLabel: RouteEndpointLabelPlacement?
    /// 종료 지점 라벨.
    let endEndpointLabel: RouteEndpointLabelPlacement?
    /// 전체 경로 색 — 0=밝은 녹색, 1=짙은 녹색.
    let traveledDarkInfluence: CGFloat
    /// 탑뷰 전환 시 선 두께 보정(1=기본, 작을수록 얇음).
    let traveledLineWidthScale: CGFloat
    /// 그라데이션 꼬리 재빌드 키 — 지나온 경로(traveled) 정점 수.
    let mapOverlayUpdateKey: Int
    /// 활성 꼬리(짧은 구간) 매 프레임 갱신 키.
    let activeTailOverlayKey: Int
    /// 활성 꼬리 끝 — 머리까지 브릿지 연결용.
    let tailAnchor: CLLocationCoordinate2D?

    init(
        traveled: [CLLocationCoordinate2D],
        activeTailSegments: [(coordinates: [CLLocationCoordinate2D], color: UIColor)],
        head: CLLocationCoordinate2D?,
        headOpacity: CGFloat = 1,
        startEndpointLabel: RouteEndpointLabelPlacement? = nil,
        endEndpointLabel: RouteEndpointLabelPlacement? = nil,
        traveledDarkInfluence: CGFloat = 0,
        traveledLineWidthScale: CGFloat = 1,
        mapOverlayUpdateKey: Int = 0,
        activeTailOverlayKey: Int = 0,
        tailAnchor: CLLocationCoordinate2D? = nil
    ) {
        self.traveled = traveled
        self.activeTailSegments = activeTailSegments
        self.head = head
        self.headOpacity = headOpacity
        self.startEndpointLabel = startEndpointLabel
        self.endEndpointLabel = endEndpointLabel
        self.traveledDarkInfluence = traveledDarkInfluence
        self.traveledLineWidthScale = traveledLineWidthScale
        self.mapOverlayUpdateKey = mapOverlayUpdateKey
        self.activeTailOverlayKey = activeTailOverlayKey
        self.tailAnchor = tailAnchor
    }

    /// 활성 꼬리를 16개 세그먼트로 나누고, 머리(밝은 녹색)에서 꼬리(짙은 녹색)로
    /// 초·중반 완만·꼬리 쪽 급격한 비선형 그라데이션을 적용합니다.
    static func gradientTailSegments(
        from coordinates: [CLLocationCoordinate2D],
        segmentCount: Int = 16
    ) -> [(coordinates: [CLLocationCoordinate2D], color: UIColor)] {
        guard coordinates.count >= 2, segmentCount > 0 else { return [] }
        let span = coordinates.count - 1
        let segments = min(segmentCount, span)
        var result: [(coordinates: [CLLocationCoordinate2D], color: UIColor)] = []
        result.reserveCapacity(segments)

        for segment in 0..<segments {
            let indexStart = (segment * span) / segments
            let indexEnd = ((segment + 1) * span) / segments
            guard indexEnd > indexStart else { continue }
            let slice = Array(coordinates[indexStart...indexEnd])
            guard slice.count >= 2 else { continue }
            let midIndex = Double(indexStart + indexEnd) / 2
            let fromHead = 1 - midIndex / Double(span)
            let darkInfluence = tailDarkInfluence(fromHead: fromHead)
            result.append((slice, FlythroughPalette.routeTailSegmentColor(darkInfluence: darkInfluence)))
        }
        return result
    }

    /// 머리(0)에서 꼬리(1)까지 — 초·중반 완만 0→40%, 꼬리 쪽 20% 구간 급격 40%→100%.
    private static func tailDarkInfluence(fromHead u: Double) -> CGFloat {
        let clamped = min(max(u, 0), 1)
        let tailSpan = 0.20
        if clamped <= 1 - tailSpan {
            let t = clamped / (1 - tailSpan)
            return CGFloat(t * 0.4)
        }
        let t = (clamped - (1 - tailSpan)) / tailSpan
        return CGFloat(0.4 + t * 0.6)
    }
}

/// 경로 polyline 역할 — 렌더러에서 색·두께를 구분합니다.
final class FlythroughRoutePolyline: MKPolyline {
    enum Role: Equatable {
        case traveled
        case activeTailSegment
    }

    var role: Role = .traveled
    var segmentColor: UIColor = FlythroughPalette.routeColor
    var lineWidthScale: CGFloat = 1
    /// 탑뷰 전경(아웃트로) — 화면 pt 고정 두께로 번져 보이지 않도록 얇은 스트로크.
    var isTopViewTraveled: Bool = false

    static func make(
        coordinates: [CLLocationCoordinate2D],
        role: Role,
        color: UIColor = FlythroughPalette.routeColor,
        lineWidthScale: CGFloat = 1,
        isTopViewTraveled: Bool = false
    ) -> FlythroughRoutePolyline {
        let line = FlythroughRoutePolyline(coordinates: coordinates, count: coordinates.count)
        line.role = role
        line.segmentColor = color
        line.lineWidthScale = lineWidthScale
        line.isTopViewTraveled = isTopViewTraveled
        return line
    }
}

/// 비행 진행 위치를 표시하는 머리 마커.
final class FlythroughProgressHeadAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}

/// 영상에 표시할 사진 — 경로 진행률(0~1)에 매핑.
struct FlythroughPhotoCue: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    /// 경로 시작점 기준 누적 거리(미터).
    let distanceMeters: CLLocationDistance
    let filename: String
}

/// 영상 프레임에 지도 위에 붙일 사진 마커.
struct FlythroughVisiblePhoto: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let thumbnail: UIImage
    let opacity: CGFloat
}

/// 렌더링에 필요한 모든 입력을 정규화해 담은 경로 모델.
struct FlythroughRoute {
    let sessionID: UUID
    let title: String
    let dateText: String
    let coordinates: [CLLocationCoordinate2D]
    let sortedPoints: [HikingPoint]
    let cumulativeDistance: [CLLocationDistance]
    let altitudes: [Double]
    let elapsedOffsets: [TimeInterval]
    let photos: [FlythroughPhotoCue]
    let kilometerMarkers: [RouteKilometerMarkerPlacement]

    let totalDistanceMeters: Double
    let totalDuration: TimeInterval
    let elevationGainMeters: Double
    let minAltitude: Double
    let maxAltitude: Double
    let sessionStartedAt: Date
    let stepCount: Int?
    let activeEnergyKilocalories: Double?
    let heartRateSamples: [HikingHeartRateSample]
    let weather: HikingRouteWeatherSnapshot?

    var totalProgressDistance: CLLocationDistance {
        cumulativeDistance.last ?? 0
    }

    var isRenderable: Bool {
        coordinates.count >= 2 && totalProgressDistance > 1
    }

    /// 경로 진행률(0~1)에서 위치/고도/시간/방향을 보간합니다.
    func sample(at progress: Double) -> FlythroughRouteSample {
        let clamped = min(max(progress, 0), 1)
        let targetDistance = clamped * totalProgressDistance
        let upperIndex = cumulativeDistance.firstIndex { $0 >= targetDistance } ?? (coordinates.count - 1)
        let index = max(upperIndex, 1)
        let lower = index - 1
        let segmentSpan = cumulativeDistance[index] - cumulativeDistance[lower]
        let t = segmentSpan > 0 ? (targetDistance - cumulativeDistance[lower]) / segmentSpan : 0

        let coordinate = FlythroughGeo.interpolate(
            from: coordinates[lower],
            to: coordinates[index],
            fraction: t
        )
        let altitude = altitudes[lower] + (altitudes[index] - altitudes[lower]) * t
        let elapsed = elapsedOffsets[lower] + (elapsedOffsets[index] - elapsedOffsets[lower]) * t
        let heading = smoothedHeading(around: targetDistance)

        return FlythroughRouteSample(
            coordinate: coordinate,
            distance: targetDistance,
            altitude: altitude,
            elapsed: elapsed,
            heading: heading
        )
    }

    /// 카메라 look-at용 — 진행률 축으로 짧게 평균해 GPS 미세 지터만 줄입니다(마커·경로선은 raw).
    func cameraLookAtCoordinate(
        at progress: Double,
        progressHalfWindow: Double = 0.012
    ) -> CLLocationCoordinate2D {
        let sampleCount = 7
        var latitude = 0.0
        var longitude = 0.0
        for index in 0..<sampleCount {
            let fraction = Double(index) / Double(max(sampleCount - 1, 1))
            let offset = (fraction - 0.5) * 2 * progressHalfWindow
            let sampleProgress = min(max(progress + offset, 0), 1)
            let coordinate = sample(at: sampleProgress).coordinate
            latitude += coordinate.latitude
            longitude += coordinate.longitude
        }
        let count = Double(sampleCount)
        return CLLocationCoordinate2D(latitude: latitude / count, longitude: longitude / count)
    }

    /// 진행률까지의 경로 좌표(드로잉용). 마지막 부분 좌표는 보간점으로 정확히 마감합니다.
    func traveledCoordinates(upTo progress: Double) -> [CLLocationCoordinate2D] {
        let clamped = min(max(progress, 0), 1)
        let targetDistance = clamped * totalProgressDistance
        var result: [CLLocationCoordinate2D] = []
        for index in coordinates.indices {
            if cumulativeDistance[index] <= targetDistance {
                result.append(coordinates[index])
            } else {
                break
            }
        }
        let head = sample(at: clamped).coordinate
        if let last = result.last,
           FlythroughGeo.distance(last, head) > 1 {
            result.append(head)
        } else if result.isEmpty {
            result.append(head)
        }
        return result
    }

    /// 누적 거리 구간에 해당하는 경로 좌표(드로잉용).
    func coordinates(fromDistance start: CLLocationDistance, toDistance end: CLLocationDistance) -> [CLLocationCoordinate2D] {
        let clampedStart = min(max(start, 0), totalProgressDistance)
        let clampedEnd = min(max(end, 0), totalProgressDistance)
        guard clampedEnd > clampedStart else {
            let head = sample(coordinateAtDistance: clampedEnd)
            return [head]
        }

        var result: [CLLocationCoordinate2D] = []
        for index in coordinates.indices {
            let distance = cumulativeDistance[index]
            if distance >= clampedStart, distance <= clampedEnd {
                result.append(coordinates[index])
            }
        }

        let startHead = sample(coordinateAtDistance: clampedStart)
        let endHead = sample(coordinateAtDistance: clampedEnd)
        if let first = result.first,
           FlythroughGeo.distance(first, startHead) > 1 {
            result.insert(startHead, at: 0)
        } else if result.isEmpty {
            result.append(startHead)
        }
        if let last = result.last,
           FlythroughGeo.distance(last, endHead) > 1 {
            result.append(endHead)
        } else if result.count == 1,
                  FlythroughGeo.distance(result[0], endHead) > 1 {
            result.append(endHead)
        }
        return result
    }

    /// 진행 끝에서 `tailMeters`만큼 되돌린 활성 꼬리 구간 — 겹치는 경로에서 현재 이동 구간을 강조합니다.
    func activeTailCoordinates(
        upTo progress: Double,
        tailMeters: CLLocationDistance = 250
    ) -> [CLLocationCoordinate2D] {
        let clamped = min(max(progress, 0), 1)
        let endDistance = clamped * totalProgressDistance
        let startDistance = max(0, endDistance - tailMeters)
        return coordinates(fromDistance: startDistance, toDistance: endDistance)
    }

    /// 지나온 경로와 활성 꼬리를 겹치지 않게 분리합니다(이중 두께 방지).
    func traveledAndActiveTail(
        upTo progress: Double,
        tailMeters: CLLocationDistance = 250
    ) -> (traveled: [CLLocationCoordinate2D], activeTail: [CLLocationCoordinate2D]) {
        let clamped = min(max(progress, 0), 1)
        guard clamped > 0.001 else {
            return (traveledCoordinates(upTo: clamped), [])
        }
        let endDistance = clamped * totalProgressDistance
        let tailStart = max(0, endDistance - tailMeters)
        let activeTail = coordinates(fromDistance: tailStart, toDistance: endDistance)
        let traveled = tailStart > 0
            ? coordinates(fromDistance: 0, toDistance: tailStart)
            : []
        return (traveled, activeTail)
    }

    /// 최종 경로 카메라 프레이밍용 — km 라벨이 좌·우로 튀어나온 범위까지 포함합니다.
    func finalRouteFramingCoordinates(labelSideOffsetMeters: CLLocationDistance = 52) -> [CLLocationCoordinate2D] {
        var result = coordinates
        result.reserveCapacity(coordinates.count + kilometerMarkers.count * 2)
        for marker in kilometerMarkers {
            result.append(marker.coordinate)
            let bearing: CLLocationDirection = marker.placesLabelOnLeadingSide ? 270 : 90
            result.append(
                FlythroughGeo.offset(marker.coordinate, meters: labelSideOffsetMeters, bearingDegrees: bearing)
            )
        }
        return result
    }

    /// 진행률까지의 누적 상승 고도(미터). 기록 상세와 동일한 스무딩·임계값 로직을 사용합니다.
    func elevationGain(upTo progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        let targetDistance = clamped * totalProgressDistance
        return HikingSessionMetrics.cumulativeElevationGain(
            from: sortedPoints,
            upToDistance: targetDistance
        )
    }

    /// 진행률에 맞춘 걸음수·심박·칼로리 표시 문자열.
    func healthMetricTexts(at progress: Double) -> (steps: String, heartRate: String, calories: String) {
        let clamped = min(max(progress, 0), 1)
        let routeSample = sample(at: clamped)

        let steps: String
        if let total = stepCount, total > 0 {
            steps = FlythroughFormat.decimal(Int((Double(total) * clamped).rounded()))
        } else {
            steps = "—"
        }

        let heartRate: String
        if let bpm = averageHeartRate(upToElapsed: routeSample.elapsed) {
            heartRate = "\(bpm) bpm"
        } else {
            heartRate = "—"
        }

        let calories: String
        if let total = activeEnergyKilocalories, total > 0 {
            let value = Int((total * clamped).rounded())
            calories = "\(FlythroughFormat.decimal(value)) kcal"
        } else {
            calories = "—"
        }

        return (steps, heartRate, calories)
    }

    private func averageHeartRate(upToElapsed elapsed: TimeInterval) -> Int? {
        guard !heartRateSamples.isEmpty else { return nil }
        let cutoff = sessionStartedAt.addingTimeInterval(elapsed)
        let samples = heartRateSamples.filter { $0.timestamp <= cutoff }
        let pool: [HikingHeartRateSample] = samples.isEmpty
            ? Array(heartRateSamples.prefix(1))
            : samples
        guard !pool.isEmpty else { return nil }
        let average = pool.map(\.bpm).reduce(0, +) / Double(pool.count)
        return Int(average.rounded())
    }

    private func smoothedHeading(around distance: CLLocationDistance) -> CLLocationDirection {
        // 앞뒤 충분히 긴 베이스라인에서 방위를 구해 GPS 떨림·미세 꺾임을 완화합니다.
        let baseline: CLLocationDistance = 500
        let back = sample(coordinateAtDistance: max(distance - baseline, 0))
        let ahead = sample(coordinateAtDistance: min(distance + baseline, totalProgressDistance))
        return FlythroughGeo.bearing(from: back, to: ahead)
    }

    private func sample(coordinateAtDistance targetDistance: CLLocationDistance) -> CLLocationCoordinate2D {
        let upperIndex = cumulativeDistance.firstIndex { $0 >= targetDistance } ?? (coordinates.count - 1)
        let index = max(upperIndex, 1)
        let lower = index - 1
        let span = cumulativeDistance[index] - cumulativeDistance[lower]
        let t = span > 0 ? (targetDistance - cumulativeDistance[lower]) / span : 0
        return FlythroughGeo.interpolate(from: coordinates[lower], to: coordinates[index], fraction: t)
    }
}

extension FlythroughRoute {
    /// 저장된 기록에서 렌더 가능한 경로 모델을 만듭니다.
    static func make(from record: SavedHikingSession) -> FlythroughRoute? {
        let sorted = record.session.points.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else { return nil }

        let coordinates = sorted.map(\.coordinate)
        let cumulative = HikingSessionMetrics.cumulativeDistances(forSorted: sorted)
        guard cumulative.count == coordinates.count, (cumulative.last ?? 0) > 1 else { return nil }

        let altitudes = sorted.map(\.altitude)
        let start = sorted.first!.timestamp
        let elapsed = sorted.map { $0.timestamp.timeIntervalSince(start) }

        let displayCoordinates = HikingTrailPhotoCoordinateLayout.displayCoordinates(
            for: record.session.photos
        )
        let photos: [FlythroughPhotoCue] = record.session.photos.compactMap { photo in
            let coordinate = photo.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
            let distanceMeters = FlythroughGeo.distanceAlongPolyline(
                to: coordinate,
                coordinates: coordinates,
                cumulative: cumulative
            )
            return FlythroughPhotoCue(
                id: photo.id,
                coordinate: displayCoordinates[photo.id] ?? coordinate,
                distanceMeters: distanceMeters,
                filename: photo.filename
            )
        }
        .sorted { $0.distanceMeters < $1.distanceMeters }

        let kilometerMarkers = HikingSessionMetrics.kilometerMarkerPlacements(from: sorted)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ko_KR")
        dateFormatter.dateFormat = "yyyy년 M월 d일"

        return FlythroughRoute(
            sessionID: record.id,
            title: Self.resolvedTitle(for: record),
            dateText: dateFormatter.string(from: record.endedAt),
            coordinates: coordinates,
            sortedPoints: sorted,
            cumulativeDistance: cumulative,
            altitudes: altitudes,
            elapsedOffsets: elapsed,
            photos: photos,
            kilometerMarkers: kilometerMarkers,
            totalDistanceMeters: record.session.totalDistance,
            totalDuration: record.session.elapsedTime,
            elevationGainMeters: record.session.elevationGainMeters
                ?? HikingSessionMetrics.cumulativeElevationGain(from: sorted),
            minAltitude: altitudes.min() ?? 0,
            maxAltitude: altitudes.max() ?? 0,
            sessionStartedAt: record.session.effectiveStartedAt ?? sorted.first!.timestamp,
            stepCount: record.session.stepCount,
            activeEnergyKilocalories: record.session.activeEnergyKilocalories,
            heartRateSamples: record.session.heartRateSamples,
            weather: record.weather
        )
    }

    /// 일반설정(지명 자동검색/타이틀 반영)에 따라 영상 타이틀을 결정합니다.
    private static func resolvedTitle(for record: SavedHikingSession) -> String {
        switch HikingFlythroughPreferences.titleSource {
        case .autoPlaceName:
            return record.session.nearbySummits?.first?.displayName ?? record.displayName ?? record.listTitle
        case .recordTitle:
            return record.displayName ?? record.listTitle
        }
    }

    /// 진행 거리(m)까지 도달한 km 라벨만 반환합니다.
    func visibleKilometerMarkers(upToProgress progress: Double) -> [RouteKilometerMarkerPlacement] {
        guard !kilometerMarkers.isEmpty else { return [] }
        let clamped = min(max(progress, 0), 1)
        let distance = sample(at: clamped).distance
        return kilometerMarkers.filter { Double($0.kilometer) * 1_000 <= distance + 25 }
    }

    /// 진행 거리 기준 표시할 사진(썸네일·투명도 포함). km 라벨과 동일하게 경로 도달 시점에 맞춥니다.
    func visiblePhotos(
        at progress: Double,
        thumbnails: [String: UIImage],
        windowBeforeMeters: CLLocationDistance = 180,
        windowAfterMeters: CLLocationDistance = 420,
        fadeOutMeters: CLLocationDistance = 90
    ) -> [FlythroughVisiblePhoto] {
        let currentDistance = sample(at: progress).distance
        return photos.compactMap { cue in
            let delta = currentDistance - cue.distanceMeters
            guard delta >= -windowBeforeMeters, delta <= windowAfterMeters else { return nil }
            guard let thumbnail = thumbnails[cue.filename] else { return nil }

            let opacity: CGFloat
            if delta < 0 {
                opacity = CGFloat((delta + windowBeforeMeters) / windowBeforeMeters)
            } else if delta > windowAfterMeters - fadeOutMeters {
                opacity = CGFloat((windowAfterMeters - delta) / fadeOutMeters)
            } else {
                opacity = 1
            }
            return FlythroughVisiblePhoto(
                id: cue.id,
                coordinate: cue.coordinate,
                thumbnail: thumbnail,
                opacity: min(max(opacity, 0), 1)
            )
        }
    }
}

/// 좌표 보간·방위·거리 헬퍼.
enum FlythroughGeo {
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func interpolate(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        fraction: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: from.latitude + (to.latitude - from.latitude) * fraction,
            longitude: from.longitude + (to.longitude - from.longitude) * fraction
        )
    }

    static func bearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> CLLocationDirection {
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        let degrees = radians * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    static func offset(
        _ coordinate: CLLocationCoordinate2D,
        meters: CLLocationDistance,
        bearingDegrees: CLLocationDirection
    ) -> CLLocationCoordinate2D {
        guard meters > 0 else { return coordinate }
        let earthRadius = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = coordinate.latitude * .pi / 180
        let lon1 = coordinate.longitude * .pi / 180
        let angular = meters / earthRadius

        let lat2 = asin(
            sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing)
        )
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }

    /// 지도 중심 기준 좌표를 bearing 방향으로 회전(탑뷰 축 정렬용).
    static func rotateCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        around center: CLLocationCoordinate2D,
        byDegrees: CLLocationDirection
    ) -> [CLLocationCoordinate2D] {
        guard abs(byDegrees.truncatingRemainder(dividingBy: 360)) > 0.01 else { return coordinates }
        let latScale = 111_320.0
        let lonScale = 111_320.0 * cos(center.latitude * .pi / 180)
        let radians = -byDegrees * .pi / 180
        let cosR = cos(radians)
        let sinR = sin(radians)
        return coordinates.map { coordinate in
            let east = (coordinate.longitude - center.longitude) * lonScale
            let north = (coordinate.latitude - center.latitude) * latScale
            let rotatedEast = east * cosR - north * sinR
            let rotatedNorth = east * sinR + north * cosR
            return CLLocationCoordinate2D(
                latitude: center.latitude + rotatedNorth / latScale,
                longitude: center.longitude + rotatedEast / lonScale
            )
        }
    }

    /// GPS 좌표를 경로 polyline에 투영한 누적 거리(미터)를 반환합니다.
    static func distanceAlongPolyline(
        to point: CLLocationCoordinate2D,
        coordinates: [CLLocationCoordinate2D],
        cumulative: [CLLocationDistance]
    ) -> CLLocationDistance {
        guard coordinates.count >= 2, cumulative.count == coordinates.count else { return 0 }

        var bestPerpendicular = Double.greatestFiniteMagnitude
        var bestAlongRoute: CLLocationDistance = 0

        for index in 0..<(coordinates.count - 1) {
            let start = coordinates[index]
            let end = coordinates[index + 1]
            let projection = closestPointOnSegment(point: point, start: start, end: end)
            if projection.perpendicularMeters < bestPerpendicular {
                bestPerpendicular = projection.perpendicularMeters
                let span = cumulative[index + 1] - cumulative[index]
                bestAlongRoute = cumulative[index] + projection.fractionAlongSegment * span
            }
        }

        return bestAlongRoute
    }

    private static func closestPointOnSegment(
        point: CLLocationCoordinate2D,
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> (fractionAlongSegment: Double, perpendicularMeters: Double) {
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        let pointLocation = CLLocation(latitude: point.latitude, longitude: point.longitude)

        let segmentLength = startLocation.distance(from: endLocation)
        guard segmentLength > 0.5 else {
            return (0, startLocation.distance(from: pointLocation))
        }

        let startX = start.longitude
        let startY = start.latitude
        let endX = end.longitude
        let endY = end.latitude
        let pointX = point.longitude
        let pointY = point.latitude

        let dx = endX - startX
        let dy = endY - startY
        let lengthSquared = dx * dx + dy * dy
        let fraction = lengthSquared > 0
            ? min(max(((pointX - startX) * dx + (pointY - startY) * dy) / lengthSquared, 0), 1)
            : 0

        let projected = CLLocationCoordinate2D(
            latitude: startY + dy * fraction,
            longitude: startX + dx * fraction
        )
        let perpendicularMeters = CLLocation(
            latitude: projected.latitude,
            longitude: projected.longitude
        ).distance(from: pointLocation)

        return (fraction, perpendicularMeters)
    }
}

#endif
