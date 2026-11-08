//
//  FlythroughPipelineContract.swift
//  sansan
//
//  3D 경로 영상 파이프라인 계약 — 불변 규칙(Invariant)과 튜닝(Tunable)의 단일 정의.
//
//  변경 가이드
//  ─────────
//  • UX·회귀에 영향 있는 규칙 → `Invariant` 수정 + `.cursor/rules/flythrough-video.mdc` 동시 갱신.
//  • 속도·화질·대기 시간만 → `FlythroughQuality` / `FlythroughVideoConfiguration`만 수정.
//  • 구현 교체(예: MKMapView → 스냅샷터) → 해당 Module 파일 + Composer 오케스트레이션.
//

#if os(iOS)

import CoreLocation
import Foundation

// MARK: - 모듈 책임 (파일 경계)

/// 파이프라인 단계별 담당 파일. 로직을 다른 모듈로 옮기기 전에 여기부터 확인.
enum FlythroughPipelineModule {
    /// 카메라 키프레임·인트로/비행/아웃트로 타이밍 — `FlythroughCameraPath.swift`
    static let cameraPath = "FlythroughCameraPath.swift"
    /// MKMapView 3D 캡처·타일 대기·경로 polyline·머리 마커 — `FlythroughMapFrameRenderer.swift`
    static let mapRenderer = "FlythroughMapFrameRenderer.swift"
    /// HUD·인트로/아웃트로 타이틀·고도 그래프 — `FlythroughOverlayRenderer.swift`
    static let overlayRenderer = "FlythroughOverlayRenderer.swift"
    /// 경로 상태·프레임 루프·MP4 — `HikingFlythroughComposer.swift`
    static let composer = "HikingFlythroughComposer.swift"
    /// 모델·화질 프리셋·`FlythroughRoute` — `FlythroughVideoModels.swift`
    static let models = "FlythroughVideoModels.swift"
    /// 활성 영역·마커 배치 — `FlythroughHUDLayout.swift`
    static let hudLayout = "FlythroughHUDLayout.swift"
}

// MARK: - 불변 규칙 (Invariant)

/// 제품 UX·시각 회귀 방지. **가급적 수정하지 않음.**
/// 변경이 필요하면 이 enum + `flythrough-video.mdc` + 관련 모듈을 함께 리뷰.
enum FlythroughPipelineInvariant {

    // MARK: 파이프라인 구조

    /// 단계 순서: 인트로 → 비행 → 아웃트로.
    static let phaseOrder: [FlythroughPhase] = [.intro, .flight, .outro]

  // MARK: 가로 / 세로

    /// 가로·세로는 카메라 거리·헤딩·활성 영역·마커 배치를 **분리** 구현. 한쪽만 맞춘 뒤 공통화 금지.
    static let portraitLandscapeLogicIsSeparate = true

    // MARK: 인트로

    /// 인트로 동안 지도에 경로선을 그리지 않음 (`HikingFlythroughComposer.routeLineState`).
    static let introShowsRouteOnMap = false

    /// 인트로: 탑뷰 전경 → 타이틀 페이드아웃 → 비행 시작점 줌인 (`FlythroughIntroTiming`).
    static let introSequenceUsesEstablishingThenZoom = true

    /// 인트로 타이틀 레이아웃: 날짜 → 산 이름 → 악센트 라인 → 날씨 (`FlythroughOverlayRenderer.drawIntro`).
    static let introWeatherBelowAccentLine = true

    // MARK: 비행

    /// 비행 시작 시 전체 경로를 미리 보여주지 않음 — 진행에 따라만 그림.
    static let flightNeverShowsFullRouteUpfront = true

    /// 비행 중 지도는 **매 프레임** 캡처 (머리·카메라 끊김 방지). stride로 생략 금지.
    static let flightCapturesMapEveryFrame = true

    /// 양자화된 꼬리 끝 → 실제 머리. `traveledAndActiveTail` 사용 시 보통 불필요(폴백).
    static let flightHeadMustBridgeToQuantizedTail = true

    /// 비행 머리·활성 꼬리 끝은 매 프레임 동일 progress. traveled만 `routeLineQuantizationSteps`로 갱신 간격.
    static let flightHeadAndTailShareExactProgress = true

    /// 세로 비행 시작점은 HUD 활성 영역 안 (`anchorPortraitActiveAreaStart`).
    static let portraitFlightStartInsideActiveArea = true

    /// 인트로 직후 — 시작점에서 머리 마커 깜박인 뒤 경로 추적 (`FlythroughFlightStartTiming`).
    static let flightStartHoldBeforeFlight = true

    /// 시작 홀드 구간에 시작 지점 라벨 표시 (`FlythroughRouteEndpointLabelAnnotation`).
    static let startHoldShowsStartEndpointLabel = true

    /// 아웃트로 홀드 첫 프레임에 종료 지점 라벨 1회 (`FlythroughRouteEndpointLabelAnnotation`).
    static let outroHoldShowsEndEndpointLabelOnce = true

    // MARK: 아웃트로

    /// 아웃트로: 비행 끝 → 탑뷰 줌아웃 → 전체 경로 고정 노출.
    static let outroZoomsToEstablishingTopView = true

    /// 아웃트로 시작 시 상단 타이틀 opacity를 0으로 떨어뜨리지 않음 (화면 튐 방지).
    static let outroKeepsFlightTitleVisible = true

    /// 아웃트로 홀드 구간은 `reusesPreviousFrame`으로 정적 카메라 재사용.
    static let outroHoldReusesFrames = true

    // MARK: 지도 캡처

    /// 오프스크린 `UIWindow` + `MKMapView` — 메인 화면 `drawHierarchy` 1순위 사용 금지.
    static let usesOffscreenMapWindow = true

    /// `mapViewDidFinishRenderingMap(fullyRendered: true)` 전에는 회색 그리드 캡처로 간주.
    /// 비행 중 연속 카메라 이동은 bounded settle — 인트로/아웃트로 정지 화면은 엄격 대기.
    static let requiresFullyRenderedTilesBeforeCapture = true

    /// Apple 법적 표기·로고는 캡처 직전에만 숨기고 즉시 복원.
    static let hidesAttributionOnlyDuringCapture = true

    /// 미로드 타일 배경 — 회색 그리드 대신 검정 (`mapView.backgroundColor`).
    static let mapBackgroundWhileTilesLoad = "black"

    /// overscan 지도 캡처 시 `drawHierarchy(in:)` destination은 항상 `(0,0,canvas)`.
    /// `mapCaptureRect`를 destination에 쓰면 좌·상단 검은 바 회귀.
    static let captureDrawsHostAtCanvasOrigin = true

    // MARK: 오버레이 / 마커

    /// 경로선·머리: MKMapView overlay/annotation. HUD·타이틀·고도: `FlythroughOverlayRenderer`.
    static let mapRouteAndHudAreSeparateLayers = true

    /// 사진 마커: 가로는 좌/우, 세로는 위. 원형 썸네일 (`FlythroughMapFrameRenderer`).
    static let photoMarkersUseLandscapeHorizontalPlacement = true

    // MARK: 경로선 스타일

    /// 비행 말미(~97%) 단일 traveled polyline으로 아웃트로 전환 정합.
    static let flightEndMergesToSingleTraveledPolyline = true
    static let flightEndMergeProgressThreshold = 0.97

    /// 비행 마지막 카메라를 잠시 유지한 뒤 아웃트로 줌 시작(기울기 끊김 방지).
    static let flightEndHoldBeforeOutro = true

    /// 아웃트로·인트로 탑뷰 전체 경로(+ km 라벨)는 HUD 활성 영역(`finalRouteFitInsets`) 안에 완전히 들어와야 함.
    static let finalRouteMustFitInsideActiveArea = true
}

// MARK: - 튜닝 상수 (숫자)

/// 성능·미세 조정 상수 — Invariant가 아닌 구현 파라미터.
enum FlythroughPipelineTuning {
    /// 비행 중 그라데이션 꼬리 구간(미터). 지나온 경로는 `traveled`로 GPS 정밀도 유지.
    static let flightActiveTailMeters: CLLocationDistance = 220.0 / 3.0
    /// 인트로 직후 시작점 고정·머리 마커 깜박임(초) — `FlythroughFlightStartTiming.blinkCount`회.
    static let flightStartHoldDuration: TimeInterval = 1.85
    /// 비행 종료 후 아웃트로 줌 전 카메라 고정(초) — 기울기 전환 끊김 방지.
    static let flightEndHoldDuration: TimeInterval = 0.65
    /// 지도 타일 여유(캡처 영역 대비). 외곽 회색 그리드 완화.
    static let mapOverscanScale: CGFloat = 1.20
    /// 탑뷰 전체 경로 줌 — look-at 보정·라벨 여백용 추가 배율.
    static let finalRouteDistanceSafetyMultiplier: Double = 1.10
    /// 탑뷰 km 라벨 버블이 바운딩 박스 밖으로 나가는 높이(미터) 추정.
    static let finalRouteMarkerVerticalPaddingMeters: CLLocationDistance = 42
}

// MARK: - 튜닝 (Tunable) — 문서

/// 속도·화질·대기 시간. **여기서 수치를 두지 않음** — 구현은 프리셋에 위임.
enum FlythroughPipelineTunable {
    /// FPS·해상도 배율·타일 대기 배율·GPU tail — `FlythroughQuality`
    static let qualityPresets = "FlythroughQuality"

    /// 인트로/비행/아웃트로 길이·지도 스타일·마커 on/off — `FlythroughVideoConfiguration`

    static let videoConfiguration = "FlythroughVideoConfiguration"

    /// 경로선 양자화 단계·그라데이션 세그먼트 수·비인트로 map stride — `FlythroughQuality`
    static let routeOverlayPerformance = "FlythroughQuality.routeLineQuantizationSteps / routeGradientSegmentCount / mapRenderStride"

    /// 비행 활성 꼬리 길이(미터) — `FlythroughPipelineTuning.flightActiveTailMeters`
    static let flightActiveTailLength = "FlythroughPipelineTuning.flightActiveTailMeters"

    /// 타일 settle·GPU drain ms — `FlythroughMapFrameRenderer` + `FlythroughQuality.timingScale`
    static let tileSettleAndGpuDrain = "FlythroughMapFrameRenderer + FlythroughQuality"

    /// 인트로 타이밍 비율 — `FlythroughIntroTiming` (UX 변경 시 Invariant와 함께 검토)
    static let introTimingFractions = "FlythroughIntroTiming"

    /// 비행 pitch·landscape 거리 envelope — `FlythroughCameraPath.flightPitch` 등
    static let cameraFramingNumbers = "FlythroughCameraPath (private static)"
}

#endif
