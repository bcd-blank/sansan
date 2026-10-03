//
//  FlythroughMapFrameRenderer.swift
//  sansan
//
//  3D(.realistic) MKMapView를 윈도우에 알파 0으로 올려 프레임별 카메라를 적용하고 비트맵을 캡처합니다.
//  계약: FlythroughPipelineContract.swift (`requiresFullyRenderedTilesBeforeCapture`, `updateHeadBridge`)
//

#if os(iOS)

import CoreLocation
import MapKit
import QuartzCore
import UIKit

@MainActor
final class FlythroughMapFrameRenderer {
    /// 캔버스 크기(포인트). 출력 픽셀 = canvasSize × renderScale.
    let canvasSize: CGSize
    let renderScale: CGFloat

    private let mapView: MKMapView
    private let observer = FlythroughRenderObserver()
    private var renderWindow: UIWindow?
    private var lastSettledCamera: MKMapCamera?

    private var traveledRouteOverlays: [FlythroughRoutePolyline] = []
    private var tailRouteOverlays: [FlythroughRoutePolyline] = []
    private var headBridgeOverlay: FlythroughRoutePolyline?
    private var routeLineStateSignature: RouteLineStateSignature?
    private var progressHeadAnnotation: FlythroughProgressHeadAnnotation?
    private var startEndpointLabelAnnotation: FlythroughRouteEndpointLabelAnnotation?
    private var endEndpointLabelAnnotation: FlythroughRouteEndpointLabelAnnotation?
    /// `setRouteLines`에서 traveled·꼬리·브릿지에 동일 선 두께 적용.
    private var lastAppliedLineWidthScale: CGFloat = 1
    /// 비행 구간 카메라 거리 — 아웃트로 줌아웃 시 선 두께 보정 기준.
    private var routeLineWidthReferenceDistance: CLLocationDistance = 800

    private struct RouteOverlayMutation {
        var traveled: Bool
        var tail: Bool
        var any: Bool { traveled || tail }
    }

    private struct RouteLineStateSignature: Equatable {
        let mapOverlayUpdateKey: Int
        let activeTailOverlayKey: Int
        let traveledCount: Int
        let activeTailSegmentCount: Int
        let traveledDarkInfluence: CGFloat
        let appliedLineWidthScale: CGFloat

        init(_ state: FlythroughRouteLineState, appliedLineWidthScale: CGFloat) {
            mapOverlayUpdateKey = state.mapOverlayUpdateKey
            activeTailOverlayKey = state.activeTailOverlayKey
            traveledCount = state.traveled.count
            activeTailSegmentCount = state.activeTailSegments.count
            traveledDarkInfluence = state.traveledDarkInfluence
            self.appliedLineWidthScale = appliedLineWidthScale
        }
    }

    private var hostContainer: UIView?

    private var photoAnnotations: [FlythroughPhotoAnnotation] = []

    private let showsPhotoMarkers: Bool
    private let showsDistanceMarkers: Bool
    private let timingScale: Double
    private let gpuDrainFullMs: Int
    private let gpuDrainLightMs: Int
    private let kilometerMarkerScale: CGFloat
    private let photoMarkerScale: CGFloat
    private let isLandscape: Bool
    private let hudLayout: FlythroughHUDLayout.Metrics
    private var kilometerAnnotations: [FlythroughKilometerAnnotation] = []
    private var cachedAttributionViews: [UIView] = []
    private var skipNextSettleFallback = false

    /// `mapOverscanScale`로 확장된 지도에서 host 클립 창에 맞출 오프셋(레이아웃 전용).
    private let mapCaptureRect: CGRect

    private let captureFormat: UIGraphicsImageRendererFormat
    private let captureRenderer: UIGraphicsImageRenderer

    init?(configuration: FlythroughVideoConfiguration) {
        guard let scene = FlythroughWindow.foregroundWindowScene else { return nil }

        // 캔버스는 기기 화면과 무관한 고정 크기(9:16/16:9) — 출력 픽셀 = 캔버스 × renderScale.
        let canvas = configuration.canvasSize
        let scale = configuration.renderScale(for: configuration.orientation)
        canvasSize = canvas
        renderScale = scale
        showsPhotoMarkers = configuration.showsPhotoMarkers
        showsDistanceMarkers = configuration.showsDistanceMarkers
        timingScale = configuration.timingScale
        gpuDrainFullMs = configuration.quality.gpuDrainFullMilliseconds
        gpuDrainLightMs = configuration.quality.gpuDrainLightMilliseconds
        kilometerMarkerScale = FlythroughHUDLayout.mapMarkerContentScale(
            orientation: configuration.orientation
        )
        photoMarkerScale = FlythroughHUDLayout.photoMarkerContentScale(
            orientation: configuration.orientation
        )
        isLandscape = configuration.orientation == .landscape
        hudLayout = FlythroughHUDLayout.metrics(
            canvasSize: canvas,
            orientation: configuration.orientation
        )

        let mapView = MKMapView(frame: CGRect(origin: .zero, size: canvas))
        let overscan = FlythroughPipelineTuning.mapOverscanScale
        let mapSize = CGSize(
            width: canvas.width * overscan,
            height: canvas.height * overscan
        )
        mapCaptureRect = CGRect(
            x: (mapSize.width - canvas.width) / 2,
            y: (mapSize.height - canvas.height) / 2,
            width: canvas.width,
            height: canvas.height
        )
        switch configuration.mapStyle {
        case .satellite:
            mapView.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        case .standard:
            mapView.preferredConfiguration = MKStandardMapConfiguration(
                elevationStyle: .realistic,
                emphasisStyle: .default
            )
        }
        mapView.overrideUserInterfaceStyle = .light
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .excludingAll
        mapView.backgroundColor = .black
        mapView.delegate = observer
        observer.routeLineWidth = configuration.orientation == .landscape ? 1 : 2
        observer.kilometerMarkerScale = kilometerMarkerScale
        observer.photoMarkerScale = photoMarkerScale
        observer.isLandscape = isLandscape
        observer.canvasSize = canvas
        observer.hudLayout = hudLayout
        self.mapView = mapView

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        captureFormat = format
        captureRenderer = UIGraphicsImageRenderer(size: canvas, format: format)

        // 메인 앱 윈도우와 분리된 오프스크린 윈도우에서 렌더(테마·trait 오염 방지).
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(
            x: -canvas.width * 2,
            y: 0,
            width: canvas.width,
            height: canvas.height
        )
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue - 1)
        window.backgroundColor = .black
        window.isHidden = false

        let root = UIViewController()
        root.view.frame = CGRect(origin: .zero, size: canvas)
        window.rootViewController = root

        let host = UIView(frame: CGRect(origin: .zero, size: canvas))
        host.isUserInteractionEnabled = false
        host.clipsToBounds = true
        mapView.frame = CGRect(
            x: -mapCaptureRect.origin.x,
            y: -mapCaptureRect.origin.y,
            width: mapSize.width,
            height: mapSize.height
        )
        host.addSubview(mapView)
        root.view.addSubview(host)

        self.renderWindow = window
        self.hostContainer = host
    }

    /// 첫 카메라를 적용한 뒤 초기 렌더를 기다립니다.
    func prepare(
        route: FlythroughRoute,
        firstCamera: MKMapCamera,
        routeLineWidthReferenceDistance: CLLocationDistance? = nil
    ) async -> Bool {
        if let reference = routeLineWidthReferenceDistance, reference > 0 {
            self.routeLineWidthReferenceDistance = reference
        }
        mapView.camera = firstCamera
        hostContainer?.layoutIfNeeded()
        mapView.layoutIfNeeded()
        installKilometerAnnotationsIfNeeded(route.kilometerMarkers)

        let rendered = await observer.waitUntilRendered(minPasses: 2, timeout: 12)
        await observer.settle(maxWait: 12, minWait: max(0.08, 0.15 * timingScale))
        try? await Task.sleep(for: .milliseconds(Int(80 * timingScale)))
        cachedAttributionViews = collectAttributionViews(in: mapView)
        lastSettledCamera = firstCamera
        return rendered
    }

    /// 인트로 종료 직후 — 비행 카메라·경로 오버레이로 위성 타일을 미리 적재합니다.
    func warmFlightStart(
        camera: MKMapCamera,
        routeLineState: FlythroughRouteLineState,
        outroTransitionFraction: Double
    ) async {
        _ = setRouteLines(
            routeLineState,
            camera: camera,
            phase: .flight,
            phaseFraction: 0,
            outroTransitionFraction: outroTransitionFraction
        )
        updateProgressHead(routeLineState.head, opacity: routeLineState.headOpacity)
        updateRouteEndpointLabels(
            start: routeLineState.startEndpointLabel,
            end: routeLineState.endEndpointLabel
        )
        mapView.setCamera(camera, animated: false)
        mapView.layoutIfNeeded()
        _ = await observer.waitUntilRendered(minPasses: 1, timeout: 4)
        await observer.settle(
            maxWait: 1.5,
            minWait: max(0.08, 0.12 * timingScale),
            absoluteCap: 2.5
        )
        try? await Task.sleep(for: .milliseconds(Int(60 * timingScale)))
        lastSettledCamera = camera
        skipNextSettleFallback = true
    }

    /// 아웃트로 시작 전 — 탑뷰(establishing) 위성 타일을 미리 적재해 회색 그리드 깜박임을 줄입니다.
    func warmOutroEstablishing(
        camera: MKMapCamera,
        routeLineState: FlythroughRouteLineState,
        outroTransitionFraction: Double
    ) async {
        _ = setRouteLines(
            routeLineState,
            camera: camera,
            phase: .outro,
            phaseFraction: 1,
            outroTransitionFraction: outroTransitionFraction
        )
        updateProgressHead(nil)
        updateRouteEndpointLabels(start: nil, end: nil)
        mapView.setCamera(camera, animated: false)
        mapView.layoutIfNeeded()
        let timeout = isLandscape ? 6.0 : 4.5
        _ = await observer.waitUntilRendered(minPasses: isLandscape ? 2 : 1, timeout: timeout)
        await observer.settle(
            maxWait: isLandscape ? 2.4 : 1.6,
            minWait: max(0.10, 0.14 * timingScale),
            absoluteCap: isLandscape ? 6.0 : 4.0
        )
        try? await Task.sleep(for: .milliseconds(Int((isLandscape ? 100 : 70) * timingScale)))
        lastSettledCamera = camera
        skipNextSettleFallback = true
    }

    /// 한 프레임을 렌더해 픽셀 비트맵을 반환합니다.
    func renderFrame(
        camera: MKMapCamera,
        routeLineState: FlythroughRouteLineState,
        phase: FlythroughPhase = .flight,
        phaseFraction: Double = 0,
        outroTransitionFraction: Double = 0.25,
        visiblePhotos: [FlythroughVisiblePhoto] = [],
        visibleKilometerMarkers: [RouteKilometerMarkerPlacement] = []
    ) async -> UIImage {
        let mutation = setRouteLines(
            routeLineState,
            camera: camera,
            phase: phase,
            phaseFraction: phaseFraction,
            outroTransitionFraction: outroTransitionFraction
        )
        updatePhotoAnnotations(visiblePhotos)
        updateKilometerAnnotations(visibleKilometerMarkers)
        mapView.setCamera(camera, animated: false)
        mapView.layoutIfNeeded()
        updateHeadBridgeIfNeeded(for: routeLineState)
        updateProgressHead(routeLineState.head, opacity: routeLineState.headOpacity)
        updateRouteEndpointLabels(
            start: routeLineState.startEndpointLabel,
            end: routeLineState.endEndpointLabel
        )
        mapView.layoutIfNeeded()

        let cameraDelta = cameraMovementDelta(for: camera)
        let skipBecauseWarm = skipNextSettleFallback
        if skipBecauseWarm {
            skipNextSettleFallback = false
        }

        if skipBecauseWarm && !mutation.traveled && camerasMatch(camera, lastSettledCamera) {
            await Task.yield()
        } else if shouldSkipTileSettle(
            for: camera,
            phase: phase,
            mutation: mutation
        ) {
            await Task.yield()
        } else {
            let settle = tileSettleTiming(
                for: camera,
                phase: phase,
                mutation: mutation,
                cameraDelta: cameraDelta
            )
            if settle.maxWait > 0 {
                await observer.settle(
                    maxWait: settle.maxWait,
                    minWait: settle.minWait,
                    absoluteCap: settle.absoluteCap
                )
            }
        }

        if phase == .flight, cameraDelta.isLarge, !observer.lastSettleFullyRendered {
            _ = await observer.waitUntilRendered(minPasses: 1, timeout: 0.8)
        }
        if phase == .outro, cameraDelta.isLarge, !observer.lastSettleFullyRendered {
            _ = await observer.waitUntilRendered(
                minPasses: 1,
                timeout: isLandscape ? 2.5 : 1.2
            )
        }

        let drainLevel = gpuDrainLevel(
            for: camera,
            overlaysMutated: mutation.traveled,
            tailMutated: mutation.tail,
            phase: phase
        )
        lastSettledCamera = camera

        await gateMapCaptureReadiness(
            phase: phase,
            mutation: mutation,
            cameraDelta: cameraDelta
        )
        await ensureFullyRenderedBeforeCapture(phase: phase)

        // 네이티브 Apple 로고·법적 표기 서브뷰를 캡처 동안만 숨깁니다.
        setCachedAttributionHidden(true)

        let captureRect = CGRect(origin: .zero, size: canvasSize)
        let image = captureRenderer.image { _ in
            // Invariant: captureDrawsHostAtCanvasOrigin — mapCaptureRect는 레이아웃 전용.
            (hostContainer ?? mapView).drawHierarchy(
                in: captureRect,
                afterScreenUpdates: true
            )
        }

        await drainGPU(level: drainLevel)
        setCachedAttributionHidden(false)

        return image
    }

    /// 사진 팝업 — MKAnnotation으로 지형·카메라 3D 투영과 동기화합니다.
    private func updatePhotoAnnotations(_ photos: [FlythroughVisiblePhoto]) {
        guard showsPhotoMarkers else {
            if !photoAnnotations.isEmpty {
                mapView.removeAnnotations(photoAnnotations)
                photoAnnotations = []
            }
            return
        }

        let nextIDs = Set(photos.map(\.id))
        let currentIDs = Set(photoAnnotations.map(\.id))

        if nextIDs != currentIDs {
            let removed = photoAnnotations.filter { !nextIDs.contains($0.id) }
            if !removed.isEmpty {
                mapView.removeAnnotations(removed)
                photoAnnotations.removeAll { !nextIDs.contains($0.id) }
            }

            let existingIDs = Set(photoAnnotations.map(\.id))
            let added = photos.filter { !existingIDs.contains($0.id) }.map(FlythroughPhotoAnnotation.init(photo:))
            if !added.isEmpty {
                photoAnnotations.append(contentsOf: added)
                mapView.addAnnotations(added)
            }
        }

        for photo in photos {
            guard let annotation = photoAnnotations.first(where: { $0.id == photo.id }) else { continue }
            annotation.opacity = photo.opacity
            if let view = mapView.view(for: annotation) as? FlythroughPhotoAnnotationView {
                view.configure(
                    with: annotation,
                    contentScale: photoMarkerScale,
                    isLandscape: isLandscape,
                    canvasSize: canvasSize,
                    layout: hudLayout,
                    mapView: mapView
                )
            }
        }

        if nextIDs != currentIDs {
            mapView.layoutIfNeeded()
        }
    }

    /// km 라벨 — prepare 시 전부 올려 두고, 도달 시점에만 표시(추가/제거 없음 → 깜박임 방지).
    private func installKilometerAnnotationsIfNeeded(_ markers: [RouteKilometerMarkerPlacement]) {
        guard showsDistanceMarkers, kilometerAnnotations.isEmpty, !markers.isEmpty else { return }
        kilometerAnnotations = markers.map {
            let annotation = FlythroughKilometerAnnotation(placement: $0)
            annotation.isVisible = false
            return annotation
        }
        mapView.addAnnotations(kilometerAnnotations)
    }

    private func updateKilometerAnnotations(_ markers: [RouteKilometerMarkerPlacement]) {
        guard showsDistanceMarkers else {
            if !kilometerAnnotations.isEmpty {
                mapView.removeAnnotations(kilometerAnnotations)
                kilometerAnnotations = []
            }
            return
        }

        let visibleIDs = Set(markers.map(\.id))
        var changed = false
        for annotation in kilometerAnnotations {
            let shouldShow = visibleIDs.contains(annotation.placement.id)
            guard annotation.isVisible != shouldShow else { continue }
            annotation.isVisible = shouldShow
            changed = true
            if let view = mapView.view(for: annotation) as? FlythroughKilometerAnnotationView {
                view.isHidden = !shouldShow
            }
        }
        if changed {
            mapView.layoutIfNeeded()
        }
    }

    /// MKMapView의 네이티브 법적 표기·Apple 로고 서브뷰를 숨김/복원합니다.
    private func collectAttributionViews(in root: UIView) -> [UIView] {
        var found: [UIView] = []
        func walk(_ view: UIView) {
            for subview in view.subviews {
                let name = String(describing: type(of: subview))
                if name.contains("Attribution")
                    || name.contains("Legal")
                    || name.contains("AppleLogo")
                    || name.contains("LogoImage") {
                    found.append(subview)
                }
                walk(subview)
            }
        }
        walk(root)
        return found
    }

    private func setCachedAttributionHidden(_ hidden: Bool) {
        if cachedAttributionViews.isEmpty {
            cachedAttributionViews = collectAttributionViews(in: mapView)
        }
        for subview in cachedAttributionViews where subview.isHidden != hidden {
            subview.isHidden = hidden
        }
    }

    @discardableResult
    private func setNativeAttributionHidden(in root: UIView, hidden: Bool) -> [UIView] {
        var affected: [UIView] = []
        func walk(_ view: UIView) {
            for subview in view.subviews {
                let name = String(describing: type(of: subview))
                if name.contains("Attribution")
                    || name.contains("Legal")
                    || name.contains("AppleLogo")
                    || name.contains("LogoImage") {
                    if subview.isHidden != hidden {
                        subview.isHidden = hidden
                        affected.append(subview)
                    }
                }
                walk(subview)
            }
        }
        walk(root)
        return affected
    }

    private struct CameraMovementDelta {
        let centerShift: CLLocationDistance
        let headingDelta: Double
        let distanceShift: CLLocationDistance
        let pitchShift: CGFloat

        var isSmall: Bool {
            centerShift < 2.5
                && headingDelta < 0.9
                && distanceShift < 8
                && pitchShift < 0.4
        }

        var isLarge: Bool {
            centerShift > 35
                || distanceShift > 40
                || headingDelta > 8
                || pitchShift > 5
        }
    }

    private func cameraMovementDelta(for camera: MKMapCamera) -> CameraMovementDelta {
        guard let previous = lastSettledCamera else {
            return CameraMovementDelta(
                centerShift: .greatestFiniteMagnitude,
                headingDelta: 180,
                distanceShift: .greatestFiniteMagnitude,
                pitchShift: 90
            )
        }
        var headingDelta = abs(previous.heading - camera.heading)
        if headingDelta > 180 { headingDelta = 360 - headingDelta }
        return CameraMovementDelta(
            centerShift: FlythroughGeo.distance(previous.centerCoordinate, camera.centerCoordinate),
            headingDelta: headingDelta,
            distanceShift: abs(previous.centerCoordinateDistance - camera.centerCoordinateDistance),
            pitchShift: abs(previous.pitch - camera.pitch)
        )
    }

    private func camerasMatch(_ lhs: MKMapCamera, _ rhs: MKMapCamera?) -> Bool {
        guard let rhs else { return false }
        var headingDelta = abs(lhs.heading - rhs.heading)
        if headingDelta > 180 { headingDelta = 360 - headingDelta }
        return FlythroughGeo.distance(lhs.centerCoordinate, rhs.centerCoordinate) < 0.5
            && headingDelta < 0.2
            && abs(lhs.centerCoordinateDistance - rhs.centerCoordinateDistance) < 0.5
            && abs(lhs.pitch - rhs.pitch) < 0.2
    }

    /// 인트로/아웃트로는 fullyRendered 엄격, 비행은 큰 카메라 이동·경로 갱신 시에만 추가 대기.
    private func gateMapCaptureReadiness(
        phase: FlythroughPhase,
        mutation: RouteOverlayMutation,
        cameraDelta: CameraMovementDelta
    ) async {
        guard FlythroughPipelineInvariant.requiresFullyRenderedTilesBeforeCapture else { return }
        guard !observer.lastSettleFullyRendered else { return }

        switch phase {
        case .intro, .outro:
            let timeout = isLandscape ? 4.0 : 2.5
            if !observer.lastSettleFullyRendered {
                _ = await observer.waitUntilRendered(minPasses: 1, timeout: timeout)
            }
            if phase == .outro, !observer.lastSettleFullyRendered {
                await observer.settle(
                    maxWait: isLandscape ? 1.6 : 1.0,
                    minWait: 0.06,
                    absoluteCap: isLandscape ? 5.0 : 3.5
                )
            }
        case .flight:
            guard mutation.traveled || cameraDelta.isLarge else { return }
            _ = await observer.waitUntilRendered(minPasses: 1, timeout: 1.0)
        }
    }

    /// 인트로·아웃트로는 fullyRendered 확인 전 캡처하지 않습니다(회색 그리드 1프레임 방지).
    private func ensureFullyRenderedBeforeCapture(phase: FlythroughPhase) async {
        guard phase == .intro || phase == .outro else { return }
        guard FlythroughPipelineInvariant.requiresFullyRenderedTilesBeforeCapture else { return }

        let maxAttempts = isLandscape ? 5 : 3
        var attempts = 0
        while !observer.lastSettleFullyRendered, attempts < maxAttempts {
            _ = await observer.waitUntilRendered(
                minPasses: 1,
                timeout: isLandscape ? 3.5 : 2.5
            )
            if observer.lastSettleFullyRendered { break }
            await observer.settle(
                maxWait: isLandscape ? 1.8 : 1.0,
                minWait: 0.05,
                absoluteCap: isLandscape ? 5.5 : 4.0
            )
            attempts += 1
        }
    }

    /// 연속 프레임에서 카메라·오버레이가 거의 안 바뀌고 직전 타일이 완전히 그려졌을 때만 대기 생략.
    private func shouldSkipTileSettle(
        for camera: MKMapCamera,
        phase: FlythroughPhase,
        mutation: RouteOverlayMutation
    ) -> Bool {
        guard observer.lastSettleFullyRendered else { return false }
        let delta = cameraMovementDelta(for: camera)
        guard delta.isSmall else { return false }

        switch phase {
        case .flight:
            return !mutation.traveled
        case .intro, .outro:
            return !mutation.traveled
        }
    }

    /// 카메라 이동량·페이즈에 따라 타일 대기 시간을 조절합니다.
    private func tileSettleTiming(
        for camera: MKMapCamera,
        phase: FlythroughPhase,
        mutation: RouteOverlayMutation,
        cameraDelta: CameraMovementDelta
    ) -> (maxWait: TimeInterval, minWait: TimeInterval, absoluteCap: TimeInterval) {
        let base: (maxWait: TimeInterval, minWait: TimeInterval)
        if phase == .flight {
            if mutation.traveled {
                base = (0.16, 0.02)
            } else if mutation.tail {
                base = (0.10, 0.015)
            } else if cameraDelta.isLarge {
                base = (0.42, 0.04)
            } else {
                base = (0.12, 0.015)
            }
            return scaled(
                base,
                phase: phase,
                mutation: mutation,
                cameraDelta: cameraDelta,
                camera: camera
            )
        }

        guard let previous = lastSettledCamera else {
            base = (0.34, 0.04)
            return scaled(
                base,
                phase: phase,
                mutation: mutation,
                cameraDelta: cameraDelta,
                camera: camera
            )
        }
        _ = previous
        if cameraDelta.isSmall {
            base = mutation.traveled ? (0.22, 0.03) : (0.14, 0.02)
        } else if cameraDelta.centerShift < 35, cameraDelta.headingDelta < 3.5, cameraDelta.distanceShift < 40 {
            base = (0.28, 0.03)
        } else if cameraDelta.distanceShift > 120 || cameraDelta.headingDelta > 12 {
            base = (0.55, 0.06)
        } else if cameraDelta.headingDelta > 8 {
            base = (0.42, 0.05)
        } else {
            base = (0.34, 0.04)
        }
        return scaled(
            base,
            phase: phase,
            mutation: mutation,
            cameraDelta: cameraDelta,
            camera: camera
        )
    }

    private func scaled(
        _ timing: (maxWait: TimeInterval, minWait: TimeInterval),
        phase: FlythroughPhase,
        mutation: RouteOverlayMutation,
        cameraDelta: CameraMovementDelta,
        camera: MKMapCamera? = nil
    ) -> (maxWait: TimeInterval, minWait: TimeInterval, absoluteCap: TimeInterval) {
        var maxWait = max(timing.maxWait * timingScale, 0.12)
        var minWait = timing.minWait * timingScale
        if mutation.traveled {
            maxWait = max(maxWait, phase == .flight ? 0.14 : 0.22)
            minWait = max(minWait, 0.02)
        }
        if phase == .flight {
            maxWait = max(maxWait, 0.12)
            minWait = max(minWait, 0.012)
            if cameraDelta.isLarge {
                maxWait = max(maxWait, 0.38)
            }
        }
        if phase == .outro {
            maxWait = max(maxWait, isLandscape ? 0.72 : 0.52)
            minWait = max(minWait, isLandscape ? 0.07 : 0.05)
        }
        if let camera, camera.pitch > 25, phase != .flight {
            maxWait = max(maxWait, 0.58)
        }

        let absoluteCap: TimeInterval
        switch phase {
        case .flight:
            if mutation.traveled {
                absoluteCap = max(maxWait * 2.0, 1.0)
            } else if cameraDelta.isLarge {
                absoluteCap = max(maxWait * 2.5, 2.0)
            } else {
                absoluteCap = max(maxWait * 2.0, 1.4)
            }
        case .outro:
            absoluteCap = max(maxWait * 3.0, isLandscape ? 4.5 : 3.0)
        case .intro:
            absoluteCap = max(maxWait * 3.0, 2.8)
        }
        return (maxWait: maxWait, minWait: minWait, absoluteCap: absoluteCap)
    }

    private enum GPUDrainLevel {
        case skip
        case light
        case full
    }

    private func gpuDrainLevel(
        for camera: MKMapCamera,
        overlaysMutated: Bool,
        tailMutated: Bool,
        phase: FlythroughPhase
    ) -> GPUDrainLevel {
        if overlaysMutated { return .full }
        if tailMutated || phase == .flight { return .light }
        guard let previous = lastSettledCamera else { return .full }
        let centerShift = FlythroughGeo.distance(previous.centerCoordinate, camera.centerCoordinate)
        var headingDelta = abs(previous.heading - camera.heading)
        if headingDelta > 180 { headingDelta = 360 - headingDelta }
        let distanceShift = abs(previous.centerCoordinateDistance - camera.centerCoordinateDistance)
        let pitchShift = abs(previous.pitch - camera.pitch)

        if centerShift < 2.5, headingDelta < 0.9, distanceShift < 8, pitchShift < 0.4 {
            return .skip
        }
        if centerShift < 35, headingDelta < 3.5, distanceShift < 40 {
            return .light
        }
        return .full
    }

    private func drainGPU(level: GPUDrainLevel = .full) async {
        switch level {
        case .skip:
            await Task.yield()
        case .light:
            try? await Task.sleep(for: .milliseconds(gpuDrainLightMs))
            await Task.yield()
        case .full:
            if !observer.lastSettleFullyRendered {
                _ = await observer.waitUntilRendered(
                    minPasses: 1,
                    timeout: max(0.45, 0.65 * timingScale)
                )
            }
            CATransaction.flush()
            mapView.layoutIfNeeded()
            let tailMs = observer.lastSettleFullyRendered ? gpuDrainLightMs : gpuDrainFullMs
            try? await Task.sleep(for: .milliseconds(tailMs))
            await Task.yield()
        }
    }

    func teardown() async {
        await drainGPU(level: .full)

        if !photoAnnotations.isEmpty {
            mapView.removeAnnotations(photoAnnotations)
            photoAnnotations = []
        }

        if !kilometerAnnotations.isEmpty {
            mapView.removeAnnotations(kilometerAnnotations)
            kilometerAnnotations = []
        }
        if !traveledRouteOverlays.isEmpty {
            mapView.removeOverlays(traveledRouteOverlays)
            traveledRouteOverlays = []
        }
        if !tailRouteOverlays.isEmpty {
            mapView.removeOverlays(tailRouteOverlays)
            tailRouteOverlays = []
        }
        removeHeadBridge()
        routeLineStateSignature = nil
        if let head = progressHeadAnnotation {
            mapView.removeAnnotation(head)
            progressHeadAnnotation = nil
        }
        removeRouteEndpointAnnotations()
        mapView.removeFromSuperview()

        await drainGPU(level: .light)

        hostContainer?.removeFromSuperview()
        hostContainer = nil
        renderWindow?.isHidden = true
        renderWindow?.rootViewController = nil
        renderWindow = nil

        try? await Task.sleep(for: .milliseconds(Int(120 * timingScale)))
    }

    private func setRouteLines(
        _ state: FlythroughRouteLineState,
        camera: MKMapCamera,
        phase: FlythroughPhase,
        phaseFraction: Double,
        outroTransitionFraction: Double
    ) -> RouteOverlayMutation {
        let lineWidthScale = effectiveLineWidthScale(
            state: state,
            camera: camera,
            phase: phase,
            phaseFraction: phaseFraction,
            outroTransitionFraction: outroTransitionFraction
        )
        lastAppliedLineWidthScale = lineWidthScale
        let signature = RouteLineStateSignature(state, appliedLineWidthScale: lineWidthScale)
        let hasOverlays = !traveledRouteOverlays.isEmpty || !tailRouteOverlays.isEmpty
        if signature == routeLineStateSignature, hasOverlays {
            return RouteOverlayMutation(traveled: false, tail: false)
        }

        let previous = routeLineStateSignature
        let traveledChanged = previous == nil
            || signature.mapOverlayUpdateKey != previous?.mapOverlayUpdateKey
            || signature.traveledCount != previous?.traveledCount
            || signature.traveledDarkInfluence != previous?.traveledDarkInfluence
            || signature.appliedLineWidthScale != previous?.appliedLineWidthScale
        let tailChanged = previous == nil
            || signature.activeTailOverlayKey != previous?.activeTailOverlayKey
            || signature.activeTailSegmentCount != previous?.activeTailSegmentCount
            || signature.appliedLineWidthScale != previous?.appliedLineWidthScale
            || traveledChanged

        if traveledChanged {
            removeTraveledRouteOverlays()
            if state.traveled.count >= 2 {
                let line = FlythroughRoutePolyline.make(
                    coordinates: state.traveled,
                    role: .traveled,
                    color: FlythroughPalette.routeTailSegmentColor(
                        darkInfluence: state.traveledDarkInfluence
                    ),
                    lineWidthScale: lineWidthScale,
                    isTopViewTraveled: phase == .outro
                )
                traveledRouteOverlays.append(line)
                mapView.addOverlay(line, level: .aboveLabels)
            }
        }

        if tailChanged {
            removeHeadBridge()
            removeTailRouteOverlays()
            for segment in state.activeTailSegments where segment.coordinates.count >= 2 {
                let line = FlythroughRoutePolyline.make(
                    coordinates: segment.coordinates,
                    role: .activeTailSegment,
                    color: segment.color,
                    lineWidthScale: lineWidthScale
                )
                tailRouteOverlays.append(line)
                mapView.addOverlay(line, level: .aboveLabels)
            }
        }

        routeLineStateSignature = signature
        return RouteOverlayMutation(traveled: traveledChanged, tail: tailChanged)
    }

    private func removeTraveledRouteOverlays() {
        guard !traveledRouteOverlays.isEmpty else { return }
        mapView.removeOverlays(traveledRouteOverlays)
        traveledRouteOverlays = []
    }

    private func removeTailRouteOverlays() {
        guard !tailRouteOverlays.isEmpty else { return }
        mapView.removeOverlays(tailRouteOverlays)
        tailRouteOverlays = []
    }

    private func updateProgressHead(_ coordinate: CLLocationCoordinate2D?, opacity: CGFloat = 1) {
        guard let coordinate else {
            if let head = progressHeadAnnotation {
                mapView.removeAnnotation(head)
                progressHeadAnnotation = nil
            }
            return
        }

        if let head = progressHeadAnnotation {
            head.coordinate = coordinate
            if let view = mapView.view(for: head) {
                view.alpha = opacity
            }
            return
        }

        let head = FlythroughProgressHeadAnnotation(coordinate: coordinate)
        progressHeadAnnotation = head
        mapView.addAnnotation(head)
        if let view = mapView.view(for: head) {
            view.alpha = opacity
        }
    }

    private func updateRouteEndpointLabels(
        start: RouteEndpointLabelPlacement?,
        end: RouteEndpointLabelPlacement?
    ) {
        updateRouteEndpointLabelAnnotation(&startEndpointLabelAnnotation, placement: start)
        updateRouteEndpointLabelAnnotation(&endEndpointLabelAnnotation, placement: end)
    }

    private func updateRouteEndpointLabelAnnotation(
        _ annotation: inout FlythroughRouteEndpointLabelAnnotation?,
        placement: RouteEndpointLabelPlacement?
    ) {
        guard let placement else {
            if let existing = annotation {
                mapView.removeAnnotation(existing)
                annotation = nil
            }
            return
        }

        if let existing = annotation {
            existing.placement = placement
            existing.coordinate = placement.coordinate
            if let view = mapView.view(for: existing) as? FlythroughRouteEndpointLabelAnnotationView {
                view.configure(with: placement, contentScale: kilometerMarkerScale)
            }
            return
        }

        let marker = FlythroughRouteEndpointLabelAnnotation(placement: placement)
        annotation = marker
        mapView.addAnnotation(marker)
        if let view = mapView.view(for: marker) as? FlythroughRouteEndpointLabelAnnotationView {
            view.configure(with: placement, contentScale: kilometerMarkerScale)
        }
    }

    private func removeRouteEndpointAnnotations() {
        if let start = startEndpointLabelAnnotation {
            mapView.removeAnnotation(start)
            startEndpointLabelAnnotation = nil
        }
        if let end = endEndpointLabelAnnotation {
            mapView.removeAnnotation(end)
            endEndpointLabelAnnotation = nil
        }
    }

    /// 활성 꼬리가 있으면 브릿지 생략. 꼬리 없을 때만 traveled 끝→머리.
    private func updateHeadBridgeIfNeeded(for state: FlythroughRouteLineState) {
        removeHeadBridge()
        guard state.activeTailSegments.isEmpty else { return }
        guard let head = state.head else { return }
        let anchor = state.traveled.last ?? state.tailAnchor
        guard let anchor else { return }
        guard FlythroughGeo.distance(anchor, head) > 1.2 else { return }

        let line = FlythroughRoutePolyline.make(
            coordinates: [anchor, head],
            role: .activeTailSegment,
            color: FlythroughPalette.routeTailSegmentColor(darkInfluence: 0),
            lineWidthScale: lastAppliedLineWidthScale
        )
        headBridgeOverlay = line
        mapView.addOverlay(line, level: .aboveLabels)
    }

    private func removeHeadBridge() {
        guard let bridge = headBridgeOverlay else { return }
        mapView.removeOverlay(bridge)
        headBridgeOverlay = nil
    }

    private func removeAllRoutePolylines() {
        removeTraveledRouteOverlays()
        removeTailRouteOverlays()
        routeLineStateSignature = nil
    }

    private func clearRouteLine() {
        removeAllRoutePolylines()
    }

    /// 비행 중에는 화면 pt 고정. 아웃트로에서는 줌아웃에 비례해 얇게 보정합니다.
    private func effectiveLineWidthScale(
        state: FlythroughRouteLineState,
        camera: MKMapCamera,
        phase: FlythroughPhase,
        phaseFraction: Double,
        outroTransitionFraction: Double
    ) -> CGFloat {
        let base = state.traveledLineWidthScale
        guard phase == .outro else { return base }
        let distance = camera.centerCoordinateDistance
        guard distance > 0, routeLineWidthReferenceDistance > 0 else { return base }
        let zoomRatio = CGFloat(routeLineWidthReferenceDistance / distance)
        let clamped = min(max(zoomRatio, 0.06), 1)
        return (clamped * 20).rounded() / 20 * base
    }
}

/// 3D 지도 주석 — MapKit이 지형·카메라에 맞춰 사진 핀을 유지합니다.
private final class FlythroughPhotoAnnotation: NSObject, MKAnnotation {
    let id: UUID
    let thumbnail: UIImage
    var opacity: CGFloat
    dynamic var coordinate: CLLocationCoordinate2D
    /// 가로 모드 좌·우 배치 — 한 번 정하면 프레임마다 바꾸지 않습니다.
    var placesLabelOnLeadingSide: Bool?

    init(photo: FlythroughVisiblePhoto) {
        id = photo.id
        thumbnail = photo.thumbnail
        opacity = photo.opacity
        coordinate = photo.coordinate
    }
}

private enum FlythroughPhotoMarkerDrawing {
    enum Layout {
        case above
        case besideLeading
        case besideTrailing
    }

    static let baseCardSize = CGSize(width: 92, height: 92)
    static let basePointerLength: CGFloat = 26
    static let basePadding: CGFloat = 4

    static func layout(isLandscape: Bool, placesLabelOnLeadingSide: Bool) -> Layout {
        guard isLandscape else { return .above }
        return placesLabelOnLeadingSide ? .besideLeading : .besideTrailing
    }

    static func markerSize(contentScale: CGFloat, layout: Layout) -> CGSize {
        let cardSize = scaledCardSize(contentScale: contentScale)
        let padding = basePadding * contentScale
        let pointerLength = basePointerLength * contentScale
        switch layout {
        case .above:
            return CGSize(
                width: cardSize.width + padding * 2,
                height: cardSize.height + pointerLength + padding * 2
            )
        case .besideLeading, .besideTrailing:
            return CGSize(
                width: cardSize.width + pointerLength + padding * 2,
                height: max(cardSize.height, pointerLength) + padding * 2
            )
        }
    }

    static func pointerTip(contentScale: CGFloat, layout: Layout) -> CGPoint {
        let cardSize = scaledCardSize(contentScale: contentScale)
        let padding = basePadding * contentScale
        let pointerLength = basePointerLength * contentScale
        let size = markerSize(contentScale: contentScale, layout: layout)
        switch layout {
        case .above:
            return CGPoint(
                x: size.width / 2,
                y: padding + cardSize.height + pointerLength
            )
        case .besideLeading:
            return CGPoint(x: size.width - padding, y: size.height / 2)
        case .besideTrailing:
            return CGPoint(x: padding, y: size.height / 2)
        }
    }

    static func centerOffset(contentScale: CGFloat, layout: Layout) -> CGPoint {
        let size = markerSize(contentScale: contentScale, layout: layout)
        let tip = pointerTip(contentScale: contentScale, layout: layout)
        return CGPoint(
            x: size.width / 2 - tip.x,
            y: size.height / 2 - tip.y
        )
    }

    private static func scaledCardSize(contentScale: CGFloat) -> CGSize {
        CGSize(
            width: baseCardSize.width * contentScale,
            height: baseCardSize.height * contentScale
        )
    }

    static func renderMarker(
        thumbnail: UIImage,
        contentScale: CGFloat,
        layout: Layout
    ) -> UIImage {
        let cardSize = scaledCardSize(contentScale: contentScale)
        let padding = basePadding * contentScale
        let pointerLength = basePointerLength * contentScale
        let size = markerSize(contentScale: contentScale, layout: layout)
        let ringWidth = 4 * contentScale
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let circleRect: CGRect
            switch layout {
            case .above:
                circleRect = CGRect(
                    x: padding,
                    y: padding,
                    width: cardSize.width,
                    height: cardSize.height
                )
            case .besideLeading:
                circleRect = CGRect(
                    x: padding,
                    y: (size.height - cardSize.height) / 2,
                    width: cardSize.width,
                    height: cardSize.height
                )
            case .besideTrailing:
                circleRect = CGRect(
                    x: size.width - padding - cardSize.width,
                    y: (size.height - cardSize.height) / 2,
                    width: cardSize.width,
                    height: cardSize.height
                )
            }

            let outerRect = circleRect.insetBy(dx: -ringWidth, dy: -ringWidth)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: outerRect).fill()

            cg.saveGState()
            UIBezierPath(ovalIn: circleRect).addClip()
            thumbnail.draw(in: circleRect)
            cg.restoreGState()

            let pointerHalfWidth = max(5, 7 * contentScale)
            let pointer = UIBezierPath()
            switch layout {
            case .above:
                pointer.move(to: CGPoint(x: circleRect.midX - pointerHalfWidth, y: circleRect.maxY))
                pointer.addLine(to: CGPoint(x: circleRect.midX + pointerHalfWidth, y: circleRect.maxY))
                pointer.addLine(to: CGPoint(x: circleRect.midX, y: circleRect.maxY + pointerLength))
            case .besideLeading:
                pointer.move(to: CGPoint(x: circleRect.maxX, y: circleRect.midY - pointerHalfWidth))
                pointer.addLine(to: CGPoint(x: circleRect.maxX, y: circleRect.midY + pointerHalfWidth))
                pointer.addLine(to: CGPoint(x: circleRect.maxX + pointerLength, y: circleRect.midY))
            case .besideTrailing:
                pointer.move(to: CGPoint(x: circleRect.minX, y: circleRect.midY - pointerHalfWidth))
                pointer.addLine(to: CGPoint(x: circleRect.minX, y: circleRect.midY + pointerHalfWidth))
                pointer.addLine(to: CGPoint(x: circleRect.minX - pointerLength, y: circleRect.midY))
            }
            pointer.close()
            pointer.fill()
        }
    }
}

private final class FlythroughPhotoAnnotationView: MKAnnotationView {
    nonisolated static let reuseID = "flythrough.photo"
    private var contentScale: CGFloat = 1

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        clipsToBounds = false
        isUserInteractionEnabled = false
        canShowCallout = false
        displayPriority = .required
        collisionMode = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(
        with photo: FlythroughPhotoAnnotation,
        contentScale: CGFloat,
        isLandscape: Bool,
        canvasSize: CGSize,
        layout: FlythroughHUDLayout.Metrics,
        mapView: MKMapView
    ) {
        self.contentScale = contentScale
        if isLandscape {
            if photo.placesLabelOnLeadingSide == nil {
                photo.placesLabelOnLeadingSide = Self.preferredLeadingSide(
                    for: photo.coordinate,
                    canvasSize: canvasSize,
                    layout: layout,
                    mapView: mapView
                )
            }
        }
        let markerLayout = FlythroughPhotoMarkerDrawing.layout(
            isLandscape: isLandscape,
            placesLabelOnLeadingSide: photo.placesLabelOnLeadingSide ?? true
        )
        centerOffset = FlythroughPhotoMarkerDrawing.centerOffset(
            contentScale: contentScale,
            layout: markerLayout
        )
        image = FlythroughPhotoMarkerDrawing.renderMarker(
            thumbnail: photo.thumbnail,
            contentScale: contentScale,
            layout: markerLayout
        )
        alpha = photo.opacity
    }

    /// 가로 모드 — 제목(좌)·통계 패널(우)을 피해 여유가 큰 쪽에 라벨을 둡니다.
    private static func preferredLeadingSide(
        for coordinate: CLLocationCoordinate2D,
        canvasSize: CGSize,
        layout: FlythroughHUDLayout.Metrics,
        mapView: MKMapView
    ) -> Bool {
        let point = mapView.convert(coordinate, toPointTo: mapView)
        let titleClearance = layout.horizontalInset + canvasSize.width * 0.18
        let statsPanelLeft = canvasSize.width - layout.horizontalInset - layout.statsPanelWidth
        let roomOnLeft = point.x - titleClearance
        let roomOnRight = statsPanelLeft - point.x
        return roomOnLeft >= roomOnRight
    }
}

/// 3D 지도 주석 — MapKit이 지형·카메라에 맞춰 경로 점을 유지합니다.
private final class FlythroughRouteEndpointLabelAnnotation: NSObject, MKAnnotation {
    var placement: RouteEndpointLabelPlacement
    dynamic var coordinate: CLLocationCoordinate2D

    init(placement: RouteEndpointLabelPlacement) {
        self.placement = placement
        coordinate = placement.coordinate
    }
}

private final class FlythroughRouteEndpointLabelAnnotationView: MKAnnotationView {
    static let reuseID = "flythrough.routeEndpointLabel"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        clipsToBounds = false
        isUserInteractionEnabled = false
        canShowCallout = false
        displayPriority = .required
        collisionMode = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(with placement: RouteEndpointLabelPlacement, contentScale: CGFloat) {
        let metrics = RouteEndpointLabelDrawing.layoutMetrics(
            kind: placement.kind,
            placesLabelOnLeadingSide: placement.placesLabelOnLeadingSide,
            contentScale: contentScale
        )
        centerOffset = CGPoint(
            x: metrics.size.width / 2 - metrics.routeDotCenter.x,
            y: metrics.size.height / 2 - metrics.routeDotCenter.y
        )
        let renderer = UIGraphicsImageRenderer(size: metrics.size)
        image = renderer.image { context in
            RouteEndpointLabelDrawing.drawMarker(
                kind: placement.kind,
                routePoint: metrics.routeDotCenter,
                placesLabelOnLeadingSide: placement.placesLabelOnLeadingSide,
                contentScale: contentScale,
                in: context.cgContext
            )
        }
    }
}

private final class FlythroughKilometerAnnotation: NSObject, MKAnnotation {
    let placement: RouteKilometerMarkerPlacement
    dynamic var coordinate: CLLocationCoordinate2D
    var isVisible = false

    init(placement: RouteKilometerMarkerPlacement) {
        self.placement = placement
        coordinate = placement.coordinate
    }
}

private final class FlythroughKilometerAnnotationView: MKAnnotationView {
    nonisolated static let reuseID = "flythrough.kilometer"

    private var routeDotCenter = CGPoint.zero
    private var labelText = ""
    private var placesLabelOnLeadingSide = false

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        clipsToBounds = false
        isUserInteractionEnabled = false
        canShowCallout = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(with marker: RouteKilometerMarkerPlacement, contentScale: CGFloat) {
        labelText = marker.labelText
        placesLabelOnLeadingSide = marker.placesLabelOnLeadingSide
        let metrics = RouteKilometerMarkerDrawing.layoutMetrics(
            label: labelText,
            placesLabelOnLeadingSide: placesLabelOnLeadingSide,
            contentScale: contentScale
        )
        routeDotCenter = metrics.routeDotCenter
        centerOffset = CGPoint(
            x: metrics.size.width / 2 - routeDotCenter.x,
            y: metrics.size.height / 2 - routeDotCenter.y
        )
        let renderer = UIGraphicsImageRenderer(size: metrics.size)
        image = renderer.image { context in
            RouteKilometerMarkerDrawing.drawMarker(
                label: labelText,
                routePoint: routeDotCenter,
                placesLabelOnLeadingSide: placesLabelOnLeadingSide,
                contentScale: contentScale,
                in: context.cgContext
            )
        }
    }
}

/// 비행 진행 위치 머리 마커 뷰.
private final class FlythroughProgressHeadAnnotationView: MKAnnotationView {
    static let reuseID = "FlythroughProgressHeadAnnotationView"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 14, height: 14)
        centerOffset = .zero
        backgroundColor = .clear
        isEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        let dot = UIBezierPath(ovalIn: rect.insetBy(dx: 3.5, dy: 3.5))
        UIColor.white.setFill()
        dot.fill()
    }
}

/// 지도 렌더 완료 콜백과 오버레이 스타일을 담당하는 델리게이트.
@MainActor
final class FlythroughRenderObserver: NSObject, MKMapViewDelegate {
    private var renderContinuation: CheckedContinuation<Bool, Never>?
    private var requiredPasses = 1
    private var passCount = 0
    private var timeoutTask: Task<Void, Never>?

    private var settleContinuation: CheckedContinuation<Void, Never>?
    private var settleTimeoutTask: Task<Void, Never>?
    var routeLineWidth: CGFloat = 3
    var kilometerMarkerScale: CGFloat = 1
    var photoMarkerScale: CGFloat = 1
    var isLandscape = false
    var canvasSize: CGSize = .zero
    var hudLayout: FlythroughHUDLayout.Metrics?
    /// 직전 `settle`이 `fullyRendered`로 끝났는지 — 연속 프레임 대기 생략·GPU tail 단축에 사용.
    private(set) var lastSettleFullyRendered = false

    func waitUntilRendered(minPasses: Int, timeout: TimeInterval) async -> Bool {
        cancelPendingRenderWait(success: false)
        requiredPasses = max(1, minPasses)
        passCount = 0
        timeoutTask?.cancel()
        return await withCheckedContinuation { continuation in
            renderContinuation = continuation
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                self.finishRender(success: self.passCount >= self.requiredPasses)
            }
        }
    }

    func settle(
        maxWait: TimeInterval,
        minWait: TimeInterval,
        absoluteCap: TimeInterval? = nil
    ) async {
        finishSettle()
        lastSettleFullyRendered = false
        let cap = max(absoluteCap ?? min(max(maxWait * 3.0, maxWait + 0.5), 4.0), maxWait)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            settleContinuation = continuation
            settleTimeoutTask?.cancel()
            settleTimeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(cap))
                self.finishSettle()
            }
        }
        if minWait > 0 {
            try? await Task.sleep(for: .seconds(minWait))
        }
    }

    private func cancelPendingRenderWait(success: Bool) {
        guard renderContinuation != nil else { return }
        finishRender(success: success)
    }

    func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
        // 회색 타일 그리드는 fullyRendered == false 일 때 — 완료로 치지 않습니다.
        guard fullyRendered else { return }
        lastSettleFullyRendered = true
        passCount += 1
        if passCount >= requiredPasses {
            finishRender(success: true)
        }
        finishSettle()
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let polyline = overlay as? FlythroughRoutePolyline else {
            return MKOverlayRenderer(overlay: overlay)
        }
        let renderer = MKPolylineRenderer(polyline: polyline)
        renderer.alpha = 1
        switch polyline.role {
        case .traveled:
            renderer.strokeColor = polyline.segmentColor.withAlphaComponent(1)
            if polyline.isTopViewTraveled {
                renderer.lineCap = .butt
                renderer.lineJoin = .bevel
                renderer.miterLimit = 1
                renderer.lineWidth = routeLineWidth * polyline.lineWidthScale
            } else {
                renderer.lineJoin = .round
                renderer.lineCap = .round
                renderer.lineWidth = max(routeLineWidth * polyline.lineWidthScale, 0.5)
            }
        case .activeTailSegment:
            renderer.lineJoin = .round
            renderer.lineCap = .round
            renderer.strokeColor = polyline.segmentColor.withAlphaComponent(1)
            renderer.lineWidth = max(routeLineWidth * polyline.lineWidthScale, 0.5)
        }
        return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is FlythroughProgressHeadAnnotation {
            let identifier = FlythroughProgressHeadAnnotationView.reuseID
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? FlythroughProgressHeadAnnotationView
                ?? FlythroughProgressHeadAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            return view
        }
        if let photo = annotation as? FlythroughPhotoAnnotation {
            let identifier = FlythroughPhotoAnnotationView.reuseID
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? FlythroughPhotoAnnotationView
                ?? FlythroughPhotoAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            let layout = hudLayout ?? FlythroughHUDLayout.metrics(
                canvasSize: canvasSize,
                orientation: isLandscape ? .landscape : .portrait
            )
            view.configure(
                with: photo,
                contentScale: photoMarkerScale,
                isLandscape: isLandscape,
                canvasSize: canvasSize,
                layout: layout,
                mapView: mapView
            )
            return view
        }
        if let endpoint = annotation as? FlythroughRouteEndpointLabelAnnotation {
            let identifier = FlythroughRouteEndpointLabelAnnotationView.reuseID
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? FlythroughRouteEndpointLabelAnnotationView
                ?? FlythroughRouteEndpointLabelAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.configure(with: endpoint.placement, contentScale: kilometerMarkerScale)
            return view
        }
        guard let kilometer = annotation as? FlythroughKilometerAnnotation else { return nil }
        let identifier = FlythroughKilometerAnnotationView.reuseID
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? FlythroughKilometerAnnotationView
            ?? FlythroughKilometerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        view.annotation = annotation
        view.configure(with: kilometer.placement, contentScale: kilometerMarkerScale)
        view.isHidden = !kilometer.isVisible
        return view
    }

    private func finishRender(success: Bool) {
        guard let continuation = renderContinuation else { return }
        renderContinuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(returning: success)
    }

    private func finishSettle() {
        guard let continuation = settleContinuation else { return }
        settleContinuation = nil
        settleTimeoutTask?.cancel()
        settleTimeoutTask = nil
        continuation.resume()
    }
}

/// 영상 전반의 강조 색(경로·고도그래프). 초록색.
enum FlythroughPalette {
    nonisolated static let routeColor = UIColor(
        red: 0.16,
        green: 0.86,
        blue: 0.38,
        alpha: 1
    )
    /// 같은 계열의 짙은 녹색 — 지나온 경로·활성 꼬리 끝.
    nonisolated static let routeDarkColor = UIColor(
        red: 0.04,
        green: 0.62,
        blue: 0.30,
        alpha: 1
    )
    /// 이미 지나온 경로 — 짙은 녹색.
    nonisolated static let routeTraveledColor = routeDarkColor

    /// 경로 색 보간 — `darkInfluence` 0=밝은 녹색, 1=짙은 녹색.
    nonisolated static func routeTailSegmentColor(darkInfluence: CGFloat) -> UIColor {
        let t = min(max(darkInfluence, 0), 1)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        routeColor.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        routeDarkColor.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            alpha: 1
        )
    }
}

@MainActor
enum FlythroughWindow {
    static var foregroundWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    static var foregroundWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .first { $0.activationState == .foregroundActive }
            .flatMap { scene in
                scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
            }
            ?? scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        return window
    }
}

#endif
