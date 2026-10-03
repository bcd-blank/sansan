//
//  RouteMapSnapshotCapture.swift
//  sansan
//
//  기록 상세 지도와 동일한 카메라·타일로 지도 베이스를 만들고, 오버레이는 합성 단계에서 그립니다.
//

#if os(iOS)

import MapKit
import QuartzCore
import SwiftUI
import UIKit

struct RouteMapSnapshotResult {
    let image: UIImage
    let mapView: MKMapView
    let captureSize: CGSize
    let includesLiveDetailContent: Bool
    let cleanup: () -> Void
}

@MainActor
enum RouteMapSnapshotCapture {
    static func capture(
        recordID: UUID,
        coordinates: [CLLocationCoordinate2D],
        mapViewSize: CGSize,
        exportSize: CGSize,
        scale: CGFloat,
        reservesLegalAttributionStrip: Bool = true,
        allowLiveDetailCapture: Bool = false,
        preferSwiftUIMapTiles: Bool = false,
        listThumbnailOnly: Bool = false
    ) async -> RouteMapSnapshotResult? {
        guard coordinates.count >= 2 else { return nil }

        guard LiveRouteMapSnapshotRegistry.shared.context(for: recordID) != nil || !allowLiveDetailCapture else {
            return await captureWithHiddenMapView(
                coordinates: coordinates,
                mapViewSize: mapViewSize,
                exportSize: exportSize,
                scale: scale,
                reservesLegalAttributionStrip: reservesLegalAttributionStrip
            )
        }

        if preferSwiftUIMapTiles {
            if listThumbnailOnly {
                if let swiftUIMap = await captureWithOffscreenSwiftUIMap(
                    coordinates: coordinates,
                    mapViewSize: mapViewSize,
                    exportSize: exportSize,
                    scale: scale,
                    reservesLegalAttributionStrip: reservesLegalAttributionStrip
                ) {
                    return swiftUIMap
                }
            } else if allowLiveDetailCapture {
                if let metalTiles = await captureSwiftUIMapMetalTiles(
                    recordID: recordID,
                    coordinates: coordinates,
                    exportSize: exportSize,
                    scale: scale,
                    reservesLegalAttributionStrip: reservesLegalAttributionStrip
                ) {
                    return metalTiles
                }

                if let visibleMap = await captureVisibleDetailMap(
                    recordID: recordID,
                    coordinates: coordinates,
                    exportSize: exportSize,
                    scale: scale,
                    reservesLegalAttributionStrip: reservesLegalAttributionStrip,
                    includesLiveDetailContent: true
                ) {
                    return visibleMap
                }
            }

            if let swiftUIMap = await captureWithOffscreenSwiftUIMap(
                coordinates: coordinates,
                mapViewSize: mapViewSize,
                exportSize: exportSize,
                scale: scale,
                reservesLegalAttributionStrip: reservesLegalAttributionStrip
            ) {
                return swiftUIMap
            }
        }

        if allowLiveDetailCapture {
            // SwiftUI Annotation(사진·로고)이 없는 클론 MKMapView — 타일만 깨끗이 가져옵니다.
            if let cloned = await captureWithOnScreenCloneMapView(
                recordID: recordID,
                coordinates: coordinates,
                exportSize: exportSize,
                scale: scale,
                reservesLegalAttributionStrip: reservesLegalAttributionStrip
            ) {
                return cloned
            }

            if let hidden = await captureWithHiddenMapView(
                recordID: recordID,
                coordinates: coordinates,
                mapViewSize: mapViewSize,
                exportSize: exportSize,
                scale: scale,
                reservesLegalAttributionStrip: reservesLegalAttributionStrip
            ) {
                return hidden
            }
        }

        return await captureWithHiddenMapView(
            coordinates: coordinates,
            mapViewSize: mapViewSize,
            exportSize: exportSize,
            scale: scale,
            reservesLegalAttributionStrip: reservesLegalAttributionStrip
        )
    }

    static func captureForGenerator(
        recordID: UUID,
        coordinates: [CLLocationCoordinate2D],
        mapViewSize: CGSize,
        exportSize: CGSize,
        scale: CGFloat,
        reservesLegalAttributionStrip: Bool,
        allowLiveDetailCapture: Bool,
        preferSwiftUIMapTiles: Bool = false,
        listThumbnailOnly: Bool = false
    ) async -> HikingRouteSnapshotGenerator.CapturedRouteMapBase? {
        guard let captured = await capture(
            recordID: recordID,
            coordinates: coordinates,
            mapViewSize: mapViewSize,
            exportSize: exportSize,
            scale: scale,
            reservesLegalAttributionStrip: reservesLegalAttributionStrip,
            allowLiveDetailCapture: allowLiveDetailCapture,
            preferSwiftUIMapTiles: preferSwiftUIMapTiles,
            listThumbnailOnly: listThumbnailOnly
        ) else { return nil }

        let mapView = captured.mapView
        let effectiveCaptureSize = captured.captureSize
        let widthScale = exportSize.width / effectiveCaptureSize.width

        return HikingRouteSnapshotGenerator.CapturedRouteMapBase(
            image: captured.image,
            pointForCoordinate: { coordinate in
                let point = mapView.convert(coordinate, toPointTo: mapView)
                return CGPoint(x: point.x * widthScale, y: point.y * widthScale)
            },
            includesLiveDetailContent: captured.includesLiveDetailContent,
            cleanup: captured.cleanup
        )
    }

    /// 상세 화면 MKMapView.takeSnapshot — 화면에 보이는 지도 타일(녹지)을 그대로 가져옵니다.
    private static func captureOnScreenMKMapViewSnapshot(
        recordID: UUID,
        exportSize: CGSize,
        scale: CGFloat,
        reservesLegalAttributionStrip: Bool
    ) async -> RouteMapSnapshotResult? {
        guard LiveRouteMapSnapshotRegistry.shared.context(for: recordID) != nil,
              let mapView = resolveOnScreenMKMapView(recordID: recordID),
              mapView.window != nil
        else { return nil }

        mapView.layoutIfNeeded()
        await waitForMapToSettle(mapView)

        let captureSize = mapView.bounds.size
        guard captureSize.width > 1, captureSize.height > 1 else { return nil }

        let screenScale = mapView.window?.screen.scale ?? scale
        let captured = renderMKMapViewBitmap(
            from: mapView,
            scale: screenScale,
            reservesLegalAttributionStrip: reservesLegalAttributionStrip
        )
        guard !isImageEffectivelyBlank(captured) else { return nil }

        let scaledImage = scaleImageUniformWidth(captured, toWidth: exportSize.width, scale: scale)

        return RouteMapSnapshotResult(
            image: scaledImage,
            mapView: mapView,
            captureSize: captureSize,
            includesLiveDetailContent: false,
            cleanup: {}
        )
    }

    /// 상세 지도와 같은 화면 좌표·카메라로 투명 MKMapView를 올려 타일 LOD를 맞춥니다.
    private static func captureWithOnScreenCloneMapView(
        recordID: UUID,
        coordinates: [CLLocationCoordinate2D],
        exportSize: CGSize,
        scale: CGFloat,
        reservesLegalAttributionStrip: Bool
    ) async -> RouteMapSnapshotResult? {
        guard let window = KeyWindow.foregroundWindow,
              let context = LiveRouteMapSnapshotRegistry.shared.context(for: recordID)
        else { return nil }

        let frameInWindow = window.convert(context.mapContentGlobalFrame, from: nil)
        guard frameInWindow.width > 1, frameInWindow.height > 1 else { return nil }

        let captureSize = context.mapSize
        let container = UIView(frame: frameInWindow)
        container.alpha = 0.01
        container.isUserInteractionEnabled = false
        container.clipsToBounds = true
        container.backgroundColor = .clear
        window.addSubview(container)

        let mapView = makeProjectionMapView(size: captureSize)
        container.addSubview(mapView)

        applyDetailCamera(to: mapView, recordID: recordID, fallbackCoordinates: context.coordinates)

        let session = RenderSession()
        mapView.delegate = session
        container.layoutIfNeeded()
        mapView.layoutIfNeeded()

        guard await session.waitUntilRendered(minPasses: 2) else {
            container.removeFromSuperview()
            return nil
        }

        try? await Task.sleep(for: .milliseconds(400))

        let screenScale = window.screen.scale
        let captured = renderMKMapViewBitmap(
            from: mapView,
            scale: screenScale,
            reservesLegalAttributionStrip: reservesLegalAttributionStrip,
            afterScreenUpdates: true
        )
        guard !isImageEffectivelyBlank(captured) else {
            container.removeFromSuperview()
            return nil
        }

        let scaledImage = scaleImageUniformWidth(captured, toWidth: exportSize.width, scale: scale)

        return RouteMapSnapshotResult(
            image: scaledImage,
            mapView: mapView,
            captureSize: captureSize,
            includesLiveDetailContent: false,
            cleanup: { container.removeFromSuperview() }
        )
    }

    /// 상세 SwiftUI Map Metal 뷰 — 녹지 타일만 윈도우 크롭.
    private static func captureSwiftUIMapMetalTiles(
        recordID: UUID,
        coordinates: [CLLocationCoordinate2D],
        exportSize: CGSize,
        scale: CGFloat,
        reservesLegalAttributionStrip: Bool
    ) async -> RouteMapSnapshotResult? {
        guard let window = KeyWindow.foregroundWindow,
              let context = LiveRouteMapSnapshotRegistry.shared.context(for: recordID),
              let renderView = LiveRouteMapSnapshotRegistry.shared.renderView(for: recordID),
              renderView.window != nil
        else { return nil }

        window.layoutIfNeeded()
        await waitForNextFrame()
        await waitForNextFrame()

        let cropRectInWindow = renderView.convert(renderView.bounds, to: window)
        guard cropRectInWindow.width > 1, cropRectInWindow.height > 1 else { return nil }

        return await finishVisibleSwiftUIMapCapture(
            recordID: recordID,
            coordinates: coordinates,
            window: window,
            cropRectInWindow: cropRectInWindow,
            exportSize: exportSize,
            scale: scale,
            reservesLegalAttributionStrip: reservesLegalAttributionStrip,
            includesLiveDetailContent: true,
            context: context
        )
    }

    /// 상세 화면에 이미 렌더된 SwiftUI Map을 윈도우 합성 버퍼에서 잘라 캡처합니다.
    private static func captureVisibleDetailMap(
        recordID: UUID,
        coordinates: [CLLocationCoordinate2D],
        exportSize: CGSize,
        scale: CGFloat,
        reservesLegalAttributionStrip: Bool,
        includesLiveDetailContent: Bool = false
    ) async -> RouteMapSnapshotResult? {
        guard let window = KeyWindow.foregroundWindow,
              let context = LiveRouteMapSnapshotRegistry.shared.context(for: recordID)
        else { return nil }

        window.layoutIfNeeded()
        await waitForNextFrame()

        let cropRectInWindow = resolveVisibleCropRect(
            recordID: recordID,
            window: window,
            context: context
        )
        guard cropRectInWindow.width > 1, cropRectInWindow.height > 1 else { return nil }

        return await finishVisibleSwiftUIMapCapture(
            recordID: recordID,
            coordinates: coordinates,
            window: window,
            cropRectInWindow: cropRectInWindow,
            exportSize: exportSize,
            scale: scale,
            reservesLegalAttributionStrip: reservesLegalAttributionStrip,
            includesLiveDetailContent: includesLiveDetailContent,
            context: context
        )
    }

    private static func finishVisibleSwiftUIMapCapture(
        recordID: UUID,
        coordinates: [CLLocationCoordinate2D],
        window: UIWindow,
        cropRectInWindow: CGRect,
        exportSize: CGSize,
        scale: CGFloat,
        reservesLegalAttributionStrip: Bool,
        includesLiveDetailContent: Bool,
        context: LiveRouteMapSnapshotRegistry.Context
    ) async -> RouteMapSnapshotResult? {
        let screenScale = window.screen.scale
        guard let captured = captureWindowCrop(
            window: window,
            cropRectInWindow: cropRectInWindow,
            scale: screenScale,
            reservesLegalAttributionStrip: reservesLegalAttributionStrip
        ), !isImageEffectivelyBlank(captured) else { return nil }

        let captureSize = CGSize(width: cropRectInWindow.width, height: cropRectInWindow.height)
        let scaledImage = scaleImageUniformWidth(captured, toWidth: exportSize.width, scale: scale)

        let projectionContainer = makeOffscreenProjectionContainer(size: captureSize, in: window)

        let projectionHost = makeProjectionMapView(size: captureSize)
        projectionContainer.addSubview(projectionHost)
        applyDetailCamera(to: projectionHost, recordID: recordID, fallbackCoordinates: context.coordinates)
        projectionHost.layoutIfNeeded()

        return RouteMapSnapshotResult(
            image: scaledImage,
            mapView: projectionHost,
            captureSize: captureSize,
            includesLiveDetailContent: includesLiveDetailContent,
            cleanup: { projectionContainer.removeFromSuperview() }
        )
    }

    /// SwiftUI Map 호스팅 뷰만 캡처 — 윈도우 크롭 시 목록·카드 UI가 비치지 않습니다.
    private static func captureSwiftUIMapHostingView(
        _ hostingView: UIView,
        scale: CGFloat,
        reservesLegalAttributionStrip: Bool
    ) -> UIImage? {
        hostingView.layoutIfNeeded()

        let size = hostingView.bounds.size
        guard size.width > 1, size.height > 1 else { return nil }

        let stripHeight = reservesLegalAttributionStrip
            ? RouteMapOverlayMetrics.mkMapCaptureAttributionStripHeight(forMapViewWidth: size.width)
            : 0
        let outputSize = CGSize(width: size.width, height: max(size.height - stripHeight, 1))

        let captureFormat = UIGraphicsImageRendererFormat()
        captureFormat.scale = scale
        captureFormat.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outputSize, format: captureFormat)
        let captured = renderer.image { context in
            if stripHeight > 0 {
                context.cgContext.clip(to: CGRect(origin: .zero, size: outputSize))
            }
            hostingView.drawHierarchy(
                in: CGRect(origin: .zero, size: size),
                afterScreenUpdates: true
            )
        }

        guard !isImageEffectivelyBlank(captured) else { return nil }
        return captured
    }

    /// 목록 썸네일 — 경로·지도만 오프스크린 SwiftUI Map으로 렌더합니다.
    private static func captureWithOffscreenSwiftUIMap(
        coordinates: [CLLocationCoordinate2D],
        mapViewSize: CGSize,
        exportSize: CGSize,
        scale: CGFloat,
        reservesLegalAttributionStrip: Bool
    ) async -> RouteMapSnapshotResult? {
        guard let window = KeyWindow.foregroundWindow else { return nil }

        let size = mapViewSize
        guard let container = makeOnScreenCaptureContainer(in: window, size: size) else { return nil }

        let rootView = ThumbnailSwiftUIMapCaptureView(coordinates: coordinates, viewSize: size)
        let hosting = UIHostingController(rootView: rootView)
        hosting.view.frame = container.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hosting.view.backgroundColor = .systemBackground
        hosting.view.isUserInteractionEnabled = false
        hosting.view.isOpaque = true
        container.addSubview(hosting.view)

        hosting.view.layoutIfNeeded()
        await waitForNextFrame()
        try? await Task.sleep(for: .milliseconds(1200))
        await waitForNextFrame()

        let screenScale = KeyWindow.foregroundWindow?.screen.scale ?? scale
        guard let captured = captureSwiftUIMapHostingView(
            hosting.view,
            scale: screenScale,
            reservesLegalAttributionStrip: reservesLegalAttributionStrip
        ) else {
            container.removeFromSuperview()
            return nil
        }

        let scaledImage = scaleImageUniformWidth(captured, toWidth: exportSize.width, scale: scale)

        let projectionContainer = makeOffscreenProjectionContainer(size: size, in: window)

        let projectionHost = makeProjectionMapView(size: size)
        projectionContainer.addSubview(projectionHost)
        fitRoute(in: projectionHost, coordinates: coordinates)
        projectionHost.layoutIfNeeded()

        return RouteMapSnapshotResult(
            image: scaledImage,
            mapView: projectionHost,
            captureSize: size,
            includesLiveDetailContent: true,
            cleanup: {
                container.removeFromSuperview()
                projectionContainer.removeFromSuperview()
            }
        )
    }

    /// 상세 지도 카메라(줌·위치)를 오프스크린 MKMapView에 복사합니다.
    private static func applyDetailCamera(
        to mapView: MKMapView,
        recordID: UUID,
        fallbackCoordinates: [CLLocationCoordinate2D]
    ) {
        // 1순위: 라이브 SwiftUI Map이 "지금" 실제로 보여주는 영역(MapProxy로 직접 산출).
        // setRegion/region 캐시는 종횡비·피팅 차이로 줌이 어긋나므로 사용하지 않습니다.
        if let liveRect = LiveRouteMapSnapshotRegistry.shared.liveVisibleMapRect(for: recordID) {
            mapView.setVisibleMapRect(liveRect, animated: false)
            return
        }
        if let onScreen = LiveRouteMapSnapshotRegistry.shared.mapView(for: recordID) {
            mapView.setVisibleMapRect(onScreen.visibleMapRect, animated: false)
            return
        }
        if let camera = LiveRouteMapSnapshotRegistry.shared.liveCamera(for: recordID) {
            if let rect = camera.visibleMapRect, !rect.isNull {
                mapView.setVisibleMapRect(rect, animated: false)
            } else {
                mapView.setRegion(camera.region, animated: false)
            }
            return
        }
        fitRoute(in: mapView, coordinates: fallbackCoordinates)
    }

    private static func resolveOnScreenMKMapView(recordID: UUID) -> MKMapView? {
        if let registered = LiveRouteMapSnapshotRegistry.shared.mapView(for: recordID),
           registered.window != nil {
            return registered
        }

        guard let context = LiveRouteMapSnapshotRegistry.shared.context(for: recordID),
              let window = KeyWindow.foregroundWindow
        else { return nil }

        let center = CGPoint(x: context.mapContentGlobalFrame.midX, y: context.mapContentGlobalFrame.midY)
        let windowPoint = window.convert(center, from: nil)
        guard let hitView = window.hitTest(windowPoint, with: nil) else { return nil }
        return MapViewLocator.findMKMapView(around: hitView)
    }

    private static func renderMKMapViewBitmap(
        from mapView: MKMapView,
        scale: CGFloat,
        reservesLegalAttributionStrip: Bool,
        afterScreenUpdates: Bool = false
    ) -> UIImage {
        let size = mapView.bounds.size

        // 네이티브 Apple 표기·로고는 MKMapView의 서브뷰입니다. 잘라내면 경로가 확대·하단으로
        // 쏠리므로, 캡처 직전에 해당 서브뷰만 숨겨 전체 높이를 그대로 떠서 경로 중심을 유지합니다.
        let hidden = reservesLegalAttributionStrip
            ? MapAttributionViewHiding.setHidden(true, in: mapView)
            : []
        defer { hidden.forEach { $0.isHidden = false } }

        let captureFormat = UIGraphicsImageRendererFormat()
        captureFormat.scale = scale
        captureFormat.opaque = true
        let captureRenderer = UIGraphicsImageRenderer(size: size, format: captureFormat)
        return captureRenderer.image { _ in
            mapView.drawHierarchy(
                in: CGRect(origin: .zero, size: size),
                afterScreenUpdates: afterScreenUpdates || reservesLegalAttributionStrip
            )
        }
    }

    private static func waitForMapToSettle(_ mapView: MKMapView) async {
        mapView.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(120))
    }

    private static func waitForNextFrame() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let target = DisplayLinkFrameWaiter {
                continuation.resume()
            }
            target.start()
        }
    }

    private static func resolveVisibleCropRect(
        recordID: UUID,
        window: UIWindow,
        context: LiveRouteMapSnapshotRegistry.Context
    ) -> CGRect {
        if let renderView = LiveRouteMapSnapshotRegistry.shared.renderView(for: recordID),
           renderView.window === window,
           renderView.bounds.width > 1,
           renderView.bounds.height > 1 {
            return renderView.convert(renderView.bounds, to: window)
        }

        let contentFrame = context.mapContentGlobalFrame
        if contentFrame.width > 1, contentFrame.height > 1 {
            return window.convert(contentFrame, from: nil)
        }

        return window.convert(context.globalFrame, from: nil)
    }

    /// Metal 지도는 개별 UIView drawHierarchy로는 녹지 레이어가 빠질 수 있어, 윈도우 합성 후 크롭합니다.
    private static func captureWindowCrop(
        window: UIWindow,
        cropRectInWindow: CGRect,
        scale: CGFloat,
        reservesLegalAttributionStrip: Bool
    ) -> UIImage? {
        let captureFormat = UIGraphicsImageRendererFormat()
        captureFormat.scale = scale
        captureFormat.opaque = true
        let captureRenderer = UIGraphicsImageRenderer(bounds: window.bounds, format: captureFormat)
        let windowImage = captureRenderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        guard var cropped = cropImage(windowImage, to: cropRectInWindow) else { return nil }

        if reservesLegalAttributionStrip {
            cropped = clipAttributionStrip(
                from: cropped,
                reservesLegalAttributionStrip: true
            )
        }

        return cropped
    }

    private static func cropImage(_ image: UIImage, to rectInPoints: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let pixelRect = CGRect(
            x: rectInPoints.origin.x * image.scale,
            y: rectInPoints.origin.y * image.scale,
            width: rectInPoints.width * image.scale,
            height: rectInPoints.height * image.scale
        ).integral

        guard pixelRect.width > 0, pixelRect.height > 0,
              let cropped = cgImage.cropping(to: pixelRect)
        else { return nil }

        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func clipAttributionStrip(
        from image: UIImage,
        reservesLegalAttributionStrip: Bool
    ) -> UIImage {
        guard reservesLegalAttributionStrip else { return image }

        let stripHeight = RouteMapOverlayMetrics.mkMapCaptureAttributionStripHeight(
            forMapViewWidth: image.size.width
        )
        return RouteMapOverlayMetrics.imageByCroppingAttributionStrip(
            from: image,
            stripHeight: stripHeight
        )
    }

    /// 상세 화면에 보이는 지도 카드와 같은 화면 좌표에 SwiftUI Map을 올려 타일(녹지)을 맞춥니다.
    private static func captureSwiftUIMapOnScreen(
        recordID: UUID,
        coordinates: [CLLocationCoordinate2D],
        mapViewSize: CGSize,
        exportSize: CGSize,
        scale: CGFloat,
        reservesLegalAttributionStrip: Bool
    ) async -> RouteMapSnapshotResult? {
        guard let window = KeyWindow.foregroundWindow,
              let context = LiveRouteMapSnapshotRegistry.shared.context(for: recordID)
        else { return nil }

        let captureSize = context.mapSize

        let frameInWindow = window.convert(context.globalFrame, from: nil)
        guard frameInWindow.width > 1, frameInWindow.height > 1 else { return nil }

        let projectionHost = makeProjectionMapView(size: captureSize)
        let projectionContainer = makeOffscreenProjectionContainer(size: captureSize, in: window)
        projectionContainer.addSubview(projectionHost)
        fitRoute(in: projectionHost, coordinates: coordinates)

        let renderSession = MapCaptureWaitSession()
        let mapState = RouteMapBaseCaptureState(
            region: HikingMapRegion.fitting(coordinates: coordinates, viewSize: captureSize)
        )
        let captureView = RouteMapBaseCaptureView(
            state: mapState,
            mapSize: captureSize,
            onCameraSettled: { renderSession.notifySettled() }
        )

        let hostingController = UIHostingController(rootView: captureView)
        AppExportAppearance.apply(to: hostingController, in: window)
        hostingController.view.frame = CGRect(
            origin: frameInWindow.origin,
            size: captureSize
        )
        hostingController.view.backgroundColor = .clear
        hostingController.view.isUserInteractionEnabled = false
        hostingController.view.clipsToBounds = true
        window.addSubview(hostingController.view)
        window.layoutIfNeeded()

        mapState.fitRoute(coordinates: coordinates, mapSize: captureSize)
        fitRoute(in: projectionHost, coordinates: coordinates)

        guard await renderSession.wait(minSettles: 2) else {
            hostingController.view.removeFromSuperview()
            projectionContainer.removeFromSuperview()
            return nil
        }

        try? await Task.sleep(for: .milliseconds(1500))

        let captured = renderMapBitmap(
            from: hostingController.view,
            size: captureSize,
            scale: scale,
            reservesLegalAttributionStrip: reservesLegalAttributionStrip
        )
        let scaledImage = scaleImageUniformWidth(captured, toWidth: exportSize.width, scale: scale)

        hostingController.view.removeFromSuperview()

        return RouteMapSnapshotResult(
            image: scaledImage,
            mapView: projectionHost,
            captureSize: captureSize,
            includesLiveDetailContent: false,
            cleanup: { projectionContainer.removeFromSuperview() }
        )
    }

    /// 목록 썸네일 등 — 화면에 거의 보이지 않게 올린 MKMapView(녹지 타일 LOD 일치).
    private static func captureWithHiddenMapView(
        recordID: UUID? = nil,
        coordinates: [CLLocationCoordinate2D],
        mapViewSize: CGSize,
        exportSize: CGSize,
        scale: CGFloat,
        reservesLegalAttributionStrip: Bool
    ) async -> RouteMapSnapshotResult? {
        guard let window = KeyWindow.foregroundWindow else { return nil }

        let size = mapViewSize
        guard let container = makeOnScreenCaptureContainer(in: window, size: size) else { return nil }

        let mapView = makeProjectionMapView(size: size)
        container.addSubview(mapView)

        let session = RenderSession()
        mapView.delegate = session

        if let recordID {
            applyDetailCamera(to: mapView, recordID: recordID, fallbackCoordinates: coordinates)
        } else {
            fitRoute(in: mapView, coordinates: coordinates)
        }
        container.layoutIfNeeded()
        mapView.layoutIfNeeded()

        guard await session.waitUntilRendered(minPasses: 2) else {
            container.removeFromSuperview()
            return nil
        }

        if let recordID {
            applyDetailCamera(to: mapView, recordID: recordID, fallbackCoordinates: coordinates)
        } else {
            fitRoute(in: mapView, coordinates: coordinates)
        }
        mapView.layoutIfNeeded()

        guard await session.waitUntilRendered(minPasses: 2) else {
            container.removeFromSuperview()
            return nil
        }

        try? await Task.sleep(for: .milliseconds(recordID == nil ? 800 : 400))
        await waitForNextFrame()
        window.bringSubviewToFront(container)

        let screenScale = KeyWindow.foregroundWindow?.screen.scale ?? scale
        let captured = captureMapContainerFromWindow(
            container: container,
            fallbackMapView: mapView,
            scale: screenScale,
            pixelScale: scale,
            reservesLegalAttributionStrip: reservesLegalAttributionStrip
        )
        guard let captured else {
            container.removeFromSuperview()
            return nil
        }
        let scaledImage = scaleImageUniformWidth(captured, toWidth: exportSize.width, scale: scale)

        return RouteMapSnapshotResult(
            image: scaledImage,
            mapView: mapView,
            captureSize: size,
            includesLiveDetailContent: false,
            cleanup: { container.removeFromSuperview() }
        )
    }

    /// Metal 지도는 윈도우 밖에 두면 녹지 타일이 빠질 수 있어 화면 안에 올립니다.
    /// UIHostingController.view가 아닌 UIWindow에 붙여 계층 경고를 피합니다.
    private static func makeOnScreenCaptureContainer(in window: UIWindow, size: CGSize) -> UIView? {
        let hostBounds = window.bounds
        let origin = CGPoint(
            x: max(hostBounds.width - size.width, 0),
            y: max(hostBounds.height - size.height, 0)
        )
        let container = UIView(frame: CGRect(origin: origin, size: size))
        container.alpha = 0.01
        container.isUserInteractionEnabled = false
        container.clipsToBounds = true
        container.backgroundColor = .clear
        window.addSubview(container)
        return container
    }

    private static func makeOffscreenProjectionContainer(size: CGSize, in window: UIWindow) -> UIView {
        let container = UIView(
            frame: CGRect(
                x: -size.width - 64,
                y: -size.height - 64,
                width: size.width,
                height: size.height
            )
        )
        container.isHidden = true
        window.addSubview(container)
        return container
    }

    /// 윈도우 합성 크롭 우선(녹지 포함) — 실패 시 MKMapView `drawHierarchy` 폴백.
    private static func captureMapContainerFromWindow(
        container: UIView,
        fallbackMapView: MKMapView,
        scale: CGFloat,
        pixelScale: CGFloat,
        reservesLegalAttributionStrip: Bool
    ) -> UIImage? {
        // 자르지 않고 네이티브 표기 서브뷰만 숨겨 전체 영역을 캡처합니다(경로 중심 유지).
        let hidden = reservesLegalAttributionStrip
            ? MapAttributionViewHiding.setHidden(true, in: container)
            : []
        defer { hidden.forEach { $0.isHidden = false } }

        if let window = container.window ?? KeyWindow.foregroundWindow {
            let cropRect = container.convert(container.bounds, to: window)
            if let windowCapture = captureWindowCrop(
                window: window,
                cropRectInWindow: cropRect,
                scale: scale,
                reservesLegalAttributionStrip: false
            ), !isImageEffectivelyBlank(windowCapture) {
                return windowCapture
            }
        }

        return captureMKMapViewTiles(
            from: fallbackMapView,
            scale: pixelScale,
            reservesLegalAttributionStrip: false
        )
    }

    /// on-screen MKMapView — Metal 녹지 타일이 `drawHierarchy`에 포함됩니다.
    private static func captureMKMapViewTiles(
        from mapView: MKMapView,
        scale: CGFloat,
        reservesLegalAttributionStrip: Bool
    ) -> UIImage? {
        let bitmap = renderMKMapViewBitmap(
            from: mapView,
            scale: scale,
            reservesLegalAttributionStrip: reservesLegalAttributionStrip,
            afterScreenUpdates: true
        )
        guard !isImageEffectivelyBlank(bitmap) else { return nil }
        return bitmap
    }

    private static func makeProjectionMapView(size: CGSize, in window: UIWindow? = nil) -> MKMapView {
        let mapView = MKMapView(frame: CGRect(origin: .zero, size: size))
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.preferredConfiguration = HikingMapCaptureConfiguration.standard
        AppExportAppearance.apply(to: mapView, in: window ?? KeyWindow.foregroundWindow)
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        return mapView
    }

    private static func renderMapBitmap(
        from contentView: UIView,
        size: CGSize,
        scale: CGFloat,
        reservesLegalAttributionStrip: Bool
    ) -> UIImage {
        let attributionStripHeight = reservesLegalAttributionStrip
            ? RouteMapOverlayMetrics.mkMapCaptureAttributionStripHeight(forMapViewWidth: size.width)
            : 0
        let mapContentHeight = max(size.height - attributionStripHeight, 1)
        let outputSize = reservesLegalAttributionStrip
            ? CGSize(width: size.width, height: mapContentHeight)
            : size

        let captureFormat = UIGraphicsImageRendererFormat()
        captureFormat.scale = scale
        captureFormat.opaque = true
        let captureRenderer = UIGraphicsImageRenderer(size: outputSize, format: captureFormat)
        return captureRenderer.image { context in
            if reservesLegalAttributionStrip {
                let clipRect = CGRect(x: 0, y: 0, width: size.width, height: mapContentHeight)
                context.cgContext.saveGState()
                context.cgContext.clip(to: clipRect)
                contentView.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
                context.cgContext.restoreGState()
            } else {
                contentView.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
            }
        }
    }

    private static func fitRoute(
        in mapView: MKMapView,
        coordinates: [CLLocationCoordinate2D]
    ) {
        guard mapView.bounds.width > 0, mapView.bounds.height > 0 else { return }
        let aspect = mapView.bounds.width / mapView.bounds.height
        let routeRect = HikingMapRegion.visibleMapRect(
            for: coordinates,
            fittingAspectRatio: aspect
        )
        guard !routeRect.isNull else { return }
        mapView.setVisibleMapRect(routeRect, animated: false)
    }

    /// Metal 지도가 아직 그려지지 않았을 때 drawHierarchy가 검정으로 나오는 경우를 걸러냅니다.
    private static func isImageEffectivelyBlank(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return true }

        let sampleWidth = min(cgImage.width, 24)
        let sampleHeight = min(cgImage.height, 24)
        guard sampleWidth > 0, sampleHeight > 0 else { return true }

        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        guard let context = CGContext(
            data: &pixels,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: sampleWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return true }

        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight)
        )

        var luminanceTotal = 0
        let pixelCount = sampleWidth * sampleHeight
        for index in 0..<pixelCount {
            let offset = index * 4
            luminanceTotal += (Int(pixels[offset])
                + Int(pixels[offset + 1])
                + Int(pixels[offset + 2])) / 3
        }

        return luminanceTotal / max(pixelCount, 1) < 24
    }

    /// 표기 스트립 크롭 후에도 종횡비를 유지합니다(세로 늘림 방지).
    private static func scaleImageUniformWidth(
        _ image: UIImage,
        toWidth targetWidth: CGFloat,
        scale: CGFloat
    ) -> UIImage {
        let aspect = image.size.height / max(image.size.width, 1)
        let size = CGSize(width: targetWidth, height: targetWidth * aspect)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

@MainActor
private final class MapCaptureWaitSession {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var settleCount = 0
    private var requiredSettles = 1
    private var timeoutTask: Task<Void, Never>?
    private var selfRetain: MapCaptureWaitSession?

    func wait(minSettles: Int) async -> Bool {
        selfRetain = self
        requiredSettles = max(1, minSettles)
        settleCount = 0
        timeoutTask?.cancel()

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                self.finish(success: self.settleCount >= self.requiredSettles)
            }
        }
    }

    func notifySettled() {
        settleCount += 1
        if settleCount >= requiredSettles {
            finish(success: true)
        }
    }

    private func finish(success: Bool) {
        guard let continuation else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        self.continuation = nil
        continuation.resume(returning: success)
        selfRetain = nil
    }
}

@MainActor
private final class RenderSession: NSObject, MKMapViewDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var didComplete = false
    private var renderPassCount = 0
    private var requiredPasses = 2
    private var timeoutTask: Task<Void, Never>?
    private var selfRetain: RenderSession?

    func waitUntilRendered(minPasses: Int = 2) async -> Bool {
        selfRetain = self
        requiredPasses = max(1, minPasses)
        renderPassCount = 0
        didComplete = false
        timeoutTask?.cancel()

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                self.finish(success: self.renderPassCount >= self.requiredPasses)
            }
        }
    }

    nonisolated func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
        guard fullyRendered else { return }
        Task { @MainActor in
            self.renderPassCount += 1
            guard self.renderPassCount >= self.requiredPasses else { return }
            self.finish(success: true)
        }
    }

    private func finish(success: Bool) {
        guard !didComplete, let continuation else { return }
        didComplete = true
        timeoutTask?.cancel()
        timeoutTask = nil
        self.continuation = nil
        continuation.resume(returning: success)
        selfRetain = nil
    }
}

@MainActor
private final class DisplayLinkFrameWaiter {
    private var displayLink: CADisplayLink?
    private let onFire: () -> Void

    init(onFire: @escaping () -> Void) {
        self.onFire = onFire
    }

    func start() {
        let link = CADisplayLink(target: self, selector: #selector(fire))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func fire() {
        displayLink?.invalidate()
        displayLink = nil
        onFire()
    }
}

@MainActor
private enum KeyWindow {
    static var foregroundWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
    }
}

#endif
