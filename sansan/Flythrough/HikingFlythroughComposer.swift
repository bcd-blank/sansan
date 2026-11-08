//
//  HikingFlythroughComposer.swift
//  sansan
//
//  3D 경로 영상 파이프라인 오케스트레이터: 경로 → 카메라 → 프레임 렌더 → 오버레이 → MP4.
//  계약: FlythroughPipelineContract.swift · `.cursor/rules/flythrough-video.mdc`
//

#if os(iOS)

import CoreLocation
import Foundation
import MapKit
import UIKit

enum FlythroughComposerError: LocalizedError {
    case routeTooShort
    case rendererUnavailable
    case cancelled

    var errorDescription: String? {
        switch self {
        case .routeTooShort:
            return "경로가 너무 짧아 영상을 만들 수 없습니다."
        case .rendererUnavailable:
            return "지도를 준비하지 못했습니다. 잠시 후 다시 시도해 주세요."
        case .cancelled:
            return "영상 생성을 취소했습니다."
        }
    }
}

@MainActor
final class HikingFlythroughComposer {
    private let configuration: FlythroughVideoConfiguration

    init(configuration: FlythroughVideoConfiguration) {
        self.configuration = configuration
    }

    /// 기록에서 3D 경로 영상을 생성합니다. 진행 단계는 `onProgress`로 통지됩니다.
    func makeVideo(
        from record: SavedHikingSession,
        onProgress: @MainActor (FlythroughProgressPhase) -> Void
    ) async throws -> URL {
        onProgress(.preparing(.analyzeRoute, progress: 0))

        guard let route = FlythroughRoute.make(from: record), route.isRenderable else {
            throw FlythroughComposerError.routeTooShort
        }

        let thumbnails = loadThumbnails(for: route, sessionID: record.id)
        let hudModel = FlythroughHUDModel.make(route: route, thumbnails: thumbnails)

        onProgress(.preparing(.analyzeRoute, progress: 1))
        onProgress(.preparing(.prepareMap, progress: 0))

        guard let frameRenderer = FlythroughMapFrameRenderer(configuration: configuration) else {
            throw FlythroughComposerError.rendererUnavailable
        }

        let directives = FlythroughCameraPath.build(
            route: route,
            configuration: configuration,
            canvasSize: frameRenderer.canvasSize
        )
        guard !directives.isEmpty else {
            await frameRenderer.teardown()
            throw FlythroughComposerError.routeTooShort
        }

        do {
            let videoURL = try await renderVideo(
                from: record,
                route: route,
                thumbnails: thumbnails,
                hudModel: hudModel,
                frameRenderer: frameRenderer,
                directives: directives,
                onProgress: onProgress
            )
            await frameRenderer.teardown()
            return videoURL
        } catch {
            await frameRenderer.teardown()
            throw error
        }
    }

    private func renderVideo(
        from record: SavedHikingSession,
        route: FlythroughRoute,
        thumbnails: [String: UIImage],
        hudModel: FlythroughHUDModel,
        frameRenderer: FlythroughMapFrameRenderer,
        directives: [FlythroughFrameDirective],
        onProgress: @MainActor (FlythroughProgressPhase) -> Void
    ) async throws -> URL {
        guard let first = directives.first else {
            throw FlythroughComposerError.routeTooShort
        }

        // 선 두께 보정 기준 = 비행 종료 카메라 거리 — 아웃트로 진입 프레임에서 scale ≈ 1 유지.
        let prepared = await frameRenderer.prepare(
            route: route,
            firstCamera: first.camera,
            routeLineWidthReferenceDistance: directives.last(where: { $0.phase == .flight })?
                .camera.centerCoordinateDistance ?? 800
        )
        if !prepared {
            // 초기 렌더가 타임아웃이어도 가능한 만큼 진행합니다(완전 검정 방지용 추가 대기).
            try? await Task.sleep(for: .milliseconds(400))
        }
        onProgress(.preparing(.prepareMap, progress: 1))

        let overlayRenderer = FlythroughOverlayRenderer(
            canvasSize: frameRenderer.canvasSize,
            renderScale: frameRenderer.renderScale,
            configuration: configuration,
            model: hudModel,
            route: route
        )

        let pixelSize = CGSize(
            width: frameRenderer.canvasSize.width * frameRenderer.renderScale,
            height: frameRenderer.canvasSize.height * frameRenderer.renderScale
        )
        let writer = try FlythroughVideoWriter(
            size: pixelSize,
            framesPerSecond: configuration.framesPerSecond
        )
        try await writer.start()

        let totalFrames = directives.count
        let segmentTotals = Self.segmentFrameTotals(directives)
        var segmentRendered: [FlythroughPhase: Int] = [.intro: 0, .flight: 0, .outro: 0]
        var lastComposedFrame: UIImage?
        var cachedBaseMap: UIImage?
        /// 직전 프레임의 픽셀 변환·인코딩 — 다음 프레임 지도 렌더와 겹칩니다(순서 보장용 1개만 유지).
        var pendingAppend: Task<Void, Error>?
        var warmedFlightStart = false
        var warmedOutroEstablishing = false
        let mapStride = max(configuration.mapRenderStride, 1)
        let outroEstablishingCamera = directives.last(where: { $0.phase == .outro })?.camera
        for (index, directive) in directives.enumerated() {
            if Task.isCancelled { throw FlythroughComposerError.cancelled }
            // 백그라운드에서는 GPU(지도 렌더·인코더) 사용이 금지되어 앱이 종료될 수 있으므로
            // 포그라운드로 돌아올 때까지 프레임 진행을 멈춥니다(진행분은 그대로 보존).
            await Self.waitUntilForegroundActive()
            if Task.isCancelled { throw FlythroughComposerError.cancelled }

            segmentRendered[directive.phase, default: 0] += 1
            let segmentFraction = Double(segmentRendered[directive.phase, default: 0])
                / Double(max(segmentTotals[directive.phase, default: 1], 1))

            // 긴 프레임 렌더 전에도 진행률이 갱신되도록(14% 부근 정지처럼 보이는 UX 방지).
            let fraction = Double(index + 1) / Double(max(totalFrames, 1))
            onProgress(.rendering(
                fraction: fraction,
                segment: Self.renderSegment(for: directive.phase),
                segmentFraction: segmentFraction
            ))

            let composed: UIImage
            if directive.reusesPreviousFrame, let cached = lastComposedFrame {
                composed = cached
            } else {
                let routeLineState = Self.routeLineState(
                    route: route,
                    directive: directive,
                    configuration: configuration
                )
                if directive.phase == .flight, !warmedFlightStart {
                    warmedFlightStart = true
                    await frameRenderer.warmFlightStart(
                        camera: directive.camera,
                        routeLineState: routeLineState,
                        outroTransitionFraction: configuration.outroTransitionFraction
                    )
                }
                if directive.phase == .outro, !warmedOutroEstablishing, let establishing = outroEstablishingCamera {
                    warmedOutroEstablishing = true
                    let establishingRouteState = Self.routeLineState(
                        route: route,
                        directive: FlythroughFrameDirective(
                            camera: establishing,
                            progress: 1,
                            phase: .outro,
                            phaseFraction: 1,
                            reusesPreviousFrame: false
                        ),
                        configuration: configuration
                    )
                    await frameRenderer.warmOutroEstablishing(
                        camera: establishing,
                        routeLineState: establishingRouteState,
                        outroTransitionFraction: configuration.outroTransitionFraction
                    )
                }
                let visiblePhotos = Self.visiblePhotos(
                    route: route,
                    directive: directive,
                    thumbnails: thumbnails,
                    enabled: configuration.showsPhotoMarkers
                )
                let visibleKilometers = Self.visibleKilometerMarkers(
                    route: route,
                    directive: directive,
                    enabled: configuration.showsDistanceMarkers
                )

                let base: UIImage
                if cachedBaseMap == nil || Self.shouldCaptureMapFrame(
                    directive: directive,
                    frameIndex: index,
                    mapStride: mapStride
                ) {
                    base = await frameRenderer.renderFrame(
                        camera: directive.camera,
                        routeLineState: routeLineState,
                        phase: directive.phase,
                        phaseFraction: directive.phaseFraction,
                        outroTransitionFraction: configuration.outroTransitionFraction,
                        visiblePhotos: visiblePhotos,
                        visibleKilometerMarkers: visibleKilometers
                    )
                    if !directive.reusesPreviousFrame {
                        cachedBaseMap = base
                    }
                } else {
                    base = cachedBaseMap!
                }

                composed = overlayRenderer.compose(
                    base: base,
                    directive: directive,
                    currentPoint: nil
                )
                lastComposedFrame = composed
            }

            // 이전 프레임 인코딩 완료를 확인한 뒤(순서·메모리 상한) 이번 프레임을 백그라운드로 넘깁니다.
            try await pendingAppend?.value
            let frame = composed
            pendingAppend = Task {
                try await writer.append(frame)
            }
        }

        try await pendingAppend?.value
        onProgress(.encoding(progress: 0))
        let videoURL = try await writer.finish()
        onProgress(.encoding(progress: 1))

        if let musicURL = bundledMusicURL() {
            if let merged = try? await FlythroughAudioMixer.merge(videoURL: videoURL, audioURL: musicURL) {
                onProgress(.finished)
                return merged
            }
        }

        onProgress(.finished)
        return videoURL
    }

    // MARK: - Helpers

    /// 앱이 백그라운드인 동안 대기합니다. 앱이 곧 중단(suspend)되므로 폴링 자체는
    /// 전환 직후 몇 초만 실행되고, 복귀 시 태스크가 깨어나 조건을 재확인합니다.
    private static func waitUntilForegroundActive() async {
        while UIApplication.shared.applicationState == .background {
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
        }
    }

    private static func routeLineState(
        route: FlythroughRoute,
        directive: FlythroughFrameDirective,
        configuration: FlythroughVideoConfiguration
    ) -> FlythroughRouteLineState {
        let endpointLabels = endpointLabels(for: route, directive: directive)
        switch directive.phase {
        case .flight:
            let progress = directive.progress
            let tailMeters = FlythroughPipelineTuning.flightActiveTailMeters
            let headCoordinate = route.sample(at: progress).coordinate
            let headOpacity = directive.headMarkerOpacity

            guard progress > 0.0001 else {
                return FlythroughRouteLineState(
                    traveled: [],
                    activeTailSegments: [],
                    head: headCoordinate,
                    headOpacity: headOpacity,
                    startEndpointLabel: endpointLabels.start,
                    endEndpointLabel: endpointLabels.end,
                    activeTailOverlayKey: 0
                )
            }

            // traveled polyline 갱신만 양자화(성능). 꼬리·머리는 매 프레임 동일 progress.
            let rebuildProgress = Self.quantizedFlightProgress(
                progress,
                steps: configuration.routeLineQuantizationSteps
            )
            let endDistance = progress * route.totalProgressDistance
            let rebuildEndDistance = rebuildProgress * route.totalProgressDistance
            let displayedTraveledEnd = max(0, rebuildEndDistance - tailMeters)

            let traveledPath: [CLLocationCoordinate2D]
            if displayedTraveledEnd > 0 {
                traveledPath = route.coordinates(
                    fromDistance: 0,
                    toDistance: displayedTraveledEnd
                )
            } else {
                traveledPath = []
            }

            // 꼬리 — 표시된 traveled 끝(또는 tailStart)부터 정확한 머리까지 매 프레임 연장.
            var activeTailPath = route.coordinates(
                fromDistance: displayedTraveledEnd,
                toDistance: endDistance
            )
            if activeTailPath.count >= 2 {
                activeTailPath[activeTailPath.count - 1] = headCoordinate
            } else if activeTailPath.count == 1 {
                activeTailPath = [activeTailPath[0], headCoordinate]
            } else {
                activeTailPath = [headCoordinate]
            }

            // 비행 말미 — 아웃트로와 동일한 단일 경로선으로 맞춰 전환 시 튐 방지.
            if progress >= FlythroughPipelineInvariant.flightEndMergeProgressThreshold {
                let mergeCoordinates = route.traveledCoordinates(upTo: progress)
                guard mergeCoordinates.count >= 2 else {
                    return FlythroughRouteLineState(
                        traveled: [],
                        activeTailSegments: [],
                        head: headCoordinate,
                        headOpacity: headOpacity,
                        startEndpointLabel: endpointLabels.start,
                        endEndpointLabel: endpointLabels.end,
                        activeTailOverlayKey: Self.activeTailOverlayKey(
                            endDistance: endDistance,
                            head: headCoordinate
                        )
                    )
                }
                return FlythroughRouteLineState(
                    traveled: mergeCoordinates,
                    activeTailSegments: [],
                    head: progress >= 0.995 ? nil : headCoordinate,
                    headOpacity: headOpacity,
                    startEndpointLabel: endpointLabels.start,
                    endEndpointLabel: endpointLabels.end,
                    traveledDarkInfluence: 1,
                    mapOverlayUpdateKey: mergeCoordinates.count,
                    activeTailOverlayKey: Self.activeTailOverlayKey(
                        endDistance: endDistance,
                        head: headCoordinate
                    ),
                    tailAnchor: mergeCoordinates.last
                )
            }

            let activeTailSegments = activeTailPath.count >= 2
                ? FlythroughRouteLineState.gradientTailSegments(
                    from: activeTailPath,
                    segmentCount: configuration.routeGradientSegmentCount
                )
                : []

            return FlythroughRouteLineState(
                traveled: traveledPath,
                activeTailSegments: activeTailSegments,
                head: headCoordinate,
                headOpacity: headOpacity,
                startEndpointLabel: endpointLabels.start,
                endEndpointLabel: endpointLabels.end,
                traveledDarkInfluence: 1,
                mapOverlayUpdateKey: Int(rebuildProgress * Double(configuration.routeLineQuantizationSteps)),
                activeTailOverlayKey: Self.activeTailOverlayKey(
                    endDistance: endDistance,
                    head: headCoordinate
                ),
                tailAnchor: activeTailPath.first ?? traveledPath.last
            )
        case .intro:
            // Invariant: FlythroughPipelineInvariant.introShowsRouteOnMap
            return FlythroughRouteLineState(
                traveled: [],
                activeTailSegments: [],
                head: nil
            )
        case .outro:
            let transitionProgress = outroRouteTransitionProgress(
                phaseFraction: directive.phaseFraction,
                transitionFraction: configuration.outroTransitionFraction
            )
            // 비행 종료(짙은 녹색) → 탑뷰(밝은 녹색)로 부드럽게 전환.
            let darkInfluence = 1 - transitionProgress
            return FlythroughRouteLineState(
                traveled: route.traveledCoordinates(upTo: 1),
                activeTailSegments: [],
                head: nil,
                startEndpointLabel: endpointLabels.start,
                endEndpointLabel: endpointLabels.end,
                traveledDarkInfluence: darkInfluence,
                traveledLineWidthScale: transitionProgress >= 0.98 ? 0.55 : 1
            )
        }
    }

    private static func endpointLabels(
        for route: FlythroughRoute,
        directive: FlythroughFrameDirective
    ) -> (start: RouteEndpointLabelPlacement?, end: RouteEndpointLabelPlacement?) {
        var start: RouteEndpointLabelPlacement?
        var end: RouteEndpointLabelPlacement?
        if directive.showsStartEndpointLabel, let coordinate = route.coordinates.first {
            start = .start(at: coordinate)
        }
        if directive.showsEndEndpointLabel, let coordinate = route.coordinates.last {
            end = .end(at: coordinate)
        }
        return (start, end)
    }

    private static func renderSegment(for phase: FlythroughPhase) -> FlythroughRenderSegment {
        switch phase {
        case .intro: return .intro
        case .flight: return .flight
        case .outro: return .outro
        }
    }

    private static func segmentFrameTotals(
        _ directives: [FlythroughFrameDirective]
    ) -> [FlythroughPhase: Int] {
        var totals: [FlythroughPhase: Int] = [.intro: 0, .flight: 0, .outro: 0]
        for directive in directives {
            totals[directive.phase, default: 0] += 1
        }
        return totals
    }

    /// traveled polyline 갱신 간격만 줄입니다. 꼬리·머리 좌표에는 사용하지 않습니다.
    private static func quantizedFlightProgress(_ progress: Double, steps: Int) -> Double {
        let clamped = min(max(progress, 0), 1)
        guard steps > 1 else { return clamped }
        return (clamped * Double(steps)).rounded() / Double(steps)
    }

    /// 활성 꼬리 매 프레임 갱신 키 — 머리·꼬리 끝 동기화.
    private static func activeTailOverlayKey(
        endDistance: CLLocationDistance,
        head: CLLocationCoordinate2D
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(Int((endDistance * 1000).rounded()))
        hasher.combine(Int((head.latitude * 1_000_000).rounded()))
        hasher.combine(Int((head.longitude * 1_000_000).rounded()))
        return hasher.finalize()
    }

    private static func outroRouteTransitionProgress(
        phaseFraction: Double,
        transitionFraction: Double
    ) -> CGFloat {
        guard transitionFraction > 0 else { return 1 }
        let raw = min(max(phaseFraction / transitionFraction, 0), 1)
        let smooth = raw * raw * (3 - 2 * raw)
        return CGFloat(smooth)
    }

    /// 비행은 매 프레임 지도 캡처(머리·브릿지 부드럽게). 인트로·아웃트로 전환도 매 프레임.
    private static func shouldCaptureMapFrame(
        directive: FlythroughFrameDirective,
        frameIndex: Int,
        mapStride: Int
    ) -> Bool {
        switch directive.phase {
        case .flight:
            return FlythroughPipelineInvariant.flightCapturesMapEveryFrame
        case .intro, .outro:
            return true
        }
    }

    private static func visiblePhotos(
        route: FlythroughRoute,
        directive: FlythroughFrameDirective,
        thumbnails: [String: UIImage],
        enabled: Bool
    ) -> [FlythroughVisiblePhoto] {
        guard enabled else { return [] }
        switch directive.phase {
        case .flight:
            return route.visiblePhotos(at: directive.progress, thumbnails: thumbnails)
        case .outro:
            return route.visiblePhotos(at: 1, thumbnails: thumbnails)
        case .intro:
            return []
        }
    }

    private static func visibleKilometerMarkers(
        route: FlythroughRoute,
        directive: FlythroughFrameDirective,
        enabled: Bool
    ) -> [RouteKilometerMarkerPlacement] {
        guard enabled else { return [] }
        switch directive.phase {
        case .flight:
            return route.visibleKilometerMarkers(upToProgress: directive.progress)
        case .outro:
            return route.visibleKilometerMarkers(upToProgress: 1)
        case .intro:
            return []
        }
    }

    private func loadThumbnails(for route: FlythroughRoute, sessionID: UUID) -> [String: UIImage] {
        var result: [String: UIImage] = [:]
        for cue in route.photos {
            guard let image = HikingTrailPhotoStore.loadImage(
                sessionID: sessionID,
                filename: cue.filename
            ) else { continue }
            result[cue.filename] = downscale(image, maxDimension: 256)
        }
        return result
    }

    private func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(maxDimension / max(size.width, 1), maxDimension / max(size.height, 1), 1)
        guard scale < 1 else { return image }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private func bundledMusicURL() -> URL? {
        for name in ["FlythroughMusic", "flythrough_music"] {
            for ext in ["m4a", "mp3", "aac"] {
                if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                    return url
                }
            }
        }
        return nil
    }
}

#endif
