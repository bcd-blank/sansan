//
//  HikingRouteSnapshotGenerator.swift
//  Shared
//

#if os(iOS)

import CoreLocation
import MapKit
import UIKit

enum HikingRouteSnapshotGenerator {
    /// 상세 화면·썸네일용 경로 이미지 (상세 지도와 동일 종횡비).
    static var routeImageSize: CGSize { HikingRouteImageLayout.exportSize }

    /// sansan 앱 — 기록 상세에 동일 recordID 지도가 화면에 있을 때만 true (라이브 스냅샷 허용).
    static var allowsLiveDetailCapture: (@MainActor (UUID) -> Bool)?

    /// sansan 앱 — 오프스크린 MKMapView 캡처(경로 전체가 중앙에 들어가도록 좌표 기준 피팅).
    static var captureRouteMapBase: (@MainActor (
        _ recordID: UUID,
        _ coordinates: [CLLocationCoordinate2D],
        _ mapViewSize: CGSize,
        _ exportSize: CGSize,
        _ scale: CGFloat,
        _ reservesLegalAttributionStrip: Bool,
        _ allowLiveDetailCapture: Bool,
        _ preferSwiftUIMapTiles: Bool,
        _ listThumbnailOnly: Bool
    ) async -> CapturedRouteMapBase?)?

    struct CapturedRouteMapBase {
        let image: UIImage
        let pointForCoordinate: (CLLocationCoordinate2D) -> CGPoint
        var includesLiveDetailContent: Bool = false
        let cleanup: () -> Void
    }
    /// 상세 지도 콘텐츠 너비(377pt) 대비 스냅샷 스케일.
    private static let mapLayoutReferenceWidth: CGFloat = 377
    private static let snapshotScale: CGFloat = 2

    private static func mapContentScale(for canvasWidth: CGFloat) -> CGFloat {
        canvasWidth / mapLayoutReferenceWidth
    }

    /// 캐시된 경로 PNG 위에 공유 옵션(사진 마커·핀 썸네일)만 빠르게 합성합니다.
    static func applyShareOverlays(
        to baseImage: UIImage,
        record: SavedHikingSession,
        mapOptions: HikingShareMapExportOptions
    ) -> UIImage {
        guard needsShareOverlays(mapOptions, record: record) else { return baseImage }

        let coordinates = HikingSessionMetrics.resolvedDisplayRouteCoordinates(from: record.session)
        let canvasSize = baseImage.size
        let region = HikingMapRegion.fitting(coordinates: coordinates, viewSize: canvasSize)
        let projector = RegionCoordinateProjector(region: region, canvasSize: canvasSize)
        let contentScale = mapContentScale(for: canvasSize.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = baseImage.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { context in
            baseImage.draw(in: CGRect(origin: .zero, size: canvasSize))
            if mapOptions.showsPhotoMarkers {
                drawPhotoMarkers(
                    using: projector,
                    photos: record.session.photos,
                    contentScale: contentScale,
                    in: context.cgContext
                )
            }
            if mapOptions.showsPinnedThumbnails, !record.mapPinnedPhotos.isEmpty {
                drawPinnedThumbnails(
                    record: record,
                    photos: record.mapPinnedPhotos,
                    contentScale: contentScale,
                    in: context.cgContext,
                    canvasSize: canvasSize
                )
            }

            if mapOptions.showsDistanceMarkers {
                drawDistanceMarkers(
                    using: projector,
                    points: record.session.points,
                    contentScale: contentScale,
                    in: context.cgContext
                )
            }

            if needsSummitOverlays(record: record) {
                drawSummitMarkers(
                    using: projector,
                    record: record,
                    contentScale: contentScale,
                    in: context.cgContext
                )
            }
        }
    }

    static func needsShareOverlays(
        _ mapOptions: HikingShareMapExportOptions,
        record: SavedHikingSession
    ) -> Bool {
        mapOptions.showsPhotoMarkers
            || (mapOptions.showsPinnedThumbnails && !record.mapPinnedPhotos.isEmpty)
            || needsDistanceMarkerOverlays(mapOptions: mapOptions, record: record)
            || needsSummitOverlays(record: record)
    }

    static func needsSummitOverlays(record: SavedHikingSession) -> Bool {
        HikingMapDisplayPreferences.showsSummitMarkers && !summits(for: record).isEmpty
    }

    static func needsDistanceMarkerOverlays(
        mapOptions: HikingShareMapExportOptions,
        record: SavedHikingSession
    ) -> Bool {
        mapOptions.showsDistanceMarkers
            && !HikingSessionMetrics.kilometerMarkerPlacements(from: record.session.points).isEmpty
    }

    static func generate(
        record: SavedHikingSession,
        style: HikingSnapshotStyle,
        mapOptions: HikingShareMapExportOptions = HikingShareExportPreferences.mapOptions,
        canvasSize: CGSize? = nil,
        pixelScale: CGFloat? = nil,
        reservesLegalAttributionStrip: Bool = true,
        allowLiveDetailCapture: Bool = false,
        preferSwiftUIMapTiles: Bool = false,
        listThumbnailOnly: Bool = false
    ) async -> UIImage? {
        let coordinates = HikingSessionMetrics.resolvedDisplayRouteCoordinates(from: record.session)
        guard coordinates.count >= 2 else { return nil }

        return await captureAndRender(
            record: record,
            coordinates: coordinates,
            fittingCoordinates: coordinates,
            mapOptions: mapOptions,
            canvasSize: canvasSize,
            pixelScale: pixelScale,
            reservesLegalAttributionStrip: reservesLegalAttributionStrip,
            allowLiveDetailCapture: allowLiveDetailCapture,
            preferSwiftUIMapTiles: preferSwiftUIMapTiles,
            listThumbnailOnly: listThumbnailOnly
        )
    }

    @MainActor
    private static func captureAndRender(
        record: SavedHikingSession,
        coordinates: [CLLocationCoordinate2D],
        fittingCoordinates: [CLLocationCoordinate2D],
        mapOptions: HikingShareMapExportOptions,
        canvasSize: CGSize?,
        pixelScale: CGFloat?,
        reservesLegalAttributionStrip: Bool,
        allowLiveDetailCapture: Bool,
        preferSwiftUIMapTiles: Bool,
        listThumbnailOnly: Bool
    ) async -> UIImage? {
        let targetCanvas = canvasSize ?? routeImageSize
        // RouteMapSnapshotCapture가 상세 화면 지도 크기를 우선 사용합니다.
        let captureMapSize = HikingRouteImageLayout.captureSize
        let scale = pixelScale ?? snapshotScale

        if let capture = captureRouteMapBase,
           let base = await capture(
            record.id,
            fittingCoordinates,
            captureMapSize,
            targetCanvas,
            scale,
            reservesLegalAttributionStrip,
            allowLiveDetailCapture,
            preferSwiftUIMapTiles,
            listThumbnailOnly
           ) {
            defer { base.cleanup() }
            let projector = ClosureCoordinateProjector(project: base.pointForCoordinate)
            // 베이스 타일은 캡처 종횡비 그대로(`scaleImageUniformWidth`)이고, 경로 투영도 동일
            // 너비 배율을 씁니다. 캔버스를 베이스 이미지 실제 크기로 맞춰야 타일과 경로가
            // 어긋나지 않습니다(고정 `targetCanvas`로 합성하면 높이 차이만큼 어긋남).
            let liveCanvas = base.image.size.width > 1 && base.image.size.height > 1
                ? base.image.size
                : targetCanvas
            return composite(
                baseImage: base.image,
                projector: projector,
                record: record,
                coordinates: coordinates,
                canvasSize: liveCanvas,
                pixelScale: scale,
                mapOptions: mapOptions,
                includesLiveDetailContent: base.includesLiveDetailContent
            )
        }

        return await captureWithSnapshotter(
            record: record,
            coordinates: coordinates,
            fittingCoordinates: fittingCoordinates,
            canvasSize: targetCanvas,
            pixelScale: scale,
            mapOptions: mapOptions,
            reservesLegalAttributionStrip: reservesLegalAttributionStrip
        )
    }

    @MainActor
    private static func captureWithSnapshotter(
        record: SavedHikingSession,
        coordinates: [CLLocationCoordinate2D],
        fittingCoordinates: [CLLocationCoordinate2D],
        canvasSize: CGSize,
        pixelScale: CGFloat,
        mapOptions: HikingShareMapExportOptions,
        reservesLegalAttributionStrip: Bool
    ) async -> UIImage? {
        // MKMapSnapshotter 이미지에는 Apple 법적 표기·로고가 포함되지 않습니다(개발자가 직접
        // 그려야 함). 따라서 strip 크롭은 실제 지도를 잘라내 경로를 어긋나게 할 뿐이라 하지 않습니다.
        let snapshotCanvas = canvasSize

        let options = MKMapSnapshotter.Options()
        // 화면 상세 지도가 "지금" 보여주는 영역을 그대로 재현합니다(없을 때만 좌표 피팅).
        let liveRect = LiveRouteMapSnapshotRegistry.shared.liveVisibleMapRect(for: record.id)
            ?? LiveRouteMapSnapshotRegistry.shared.liveCamera(for: record.id)?.visibleMapRect
        if let liveRect, !liveRect.isNull {
            options.region = MKCoordinateRegion(liveRect)
        } else {
            options.region = HikingMapRegion.fitting(
                coordinates: fittingCoordinates,
                viewSize: snapshotCanvas
            )
        }
        options.size = snapshotCanvas
        options.scale = pixelScale
        options.preferredConfiguration = HikingMapCaptureConfiguration.standard
        options.traitCollection = UITraitCollection(
            userInterfaceStyle: AppExportAppearance.resolvedUserInterfaceStyle()
        )

        return await withCheckedContinuation { continuation in
            MKMapSnapshotter(options: options).start { snapshot, error in
                guard let snapshot, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }

                let projector = SnapshotCoordinateProjector(snapshot: snapshot)
                let baseImage = snapshot.image
                let image = composite(
                    baseImage: baseImage,
                    projector: projector,
                    record: record,
                    coordinates: coordinates,
                    canvasSize: canvasSize,
                    pixelScale: pixelScale,
                    mapOptions: mapOptions
                )
                continuation.resume(returning: image)
            }
        }
    }

    private static func composite(
        baseImage: UIImage,
        projector: MapCoordinateProjecting,
        record: SavedHikingSession,
        coordinates: [CLLocationCoordinate2D],
        canvasSize: CGSize,
        pixelScale: CGFloat,
        mapOptions: HikingShareMapExportOptions,
        includesLiveDetailContent: Bool = false
    ) -> UIImage {
        let contentScale = mapContentScale(for: canvasSize.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = pixelScale
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { context in
            baseImage.draw(in: CGRect(origin: .zero, size: canvasSize))

            if !includesLiveDetailContent {
                drawRoute(
                    using: projector,
                    coordinates: coordinates,
                    contentScale: contentScale,
                    in: context.cgContext
                )
                drawEndpoints(
                    using: projector,
                    coordinates: coordinates,
                    contentScale: contentScale,
                    in: context.cgContext
                )

                if mapOptions.showsPhotoMarkers {
                    drawPhotoMarkers(
                        using: projector,
                        photos: record.session.photos,
                        contentScale: contentScale,
                        in: context.cgContext
                    )
                }

                if mapOptions.showsDistanceMarkers {
                    drawDistanceMarkers(
                        using: projector,
                        points: record.session.points,
                        contentScale: contentScale,
                        in: context.cgContext
                    )
                }
            }

            if needsSummitOverlays(record: record) {
                drawSummitMarkers(
                    using: projector,
                    record: record,
                    contentScale: contentScale,
                    in: context.cgContext
                )
            }

            if mapOptions.showsPinnedThumbnails, !record.mapPinnedPhotos.isEmpty {
                drawPinnedThumbnails(
                    record: record,
                    photos: record.mapPinnedPhotos,
                    contentScale: contentScale,
                    in: context.cgContext,
                    canvasSize: canvasSize
                )
            }
        }
    }

    /// 지도 캡처 하단 Apple 법적 표기 영역을 잘라 카드 레이어로 덮을 수 있게 합니다.
    static func mapBaseExcludingAttributionStrip(
        from image: UIImage,
        canvasWidth: CGFloat
    ) -> UIImage {
        let stripHeight = RouteMapOverlayMetrics.mkMapCaptureAttributionStripHeight(
            forMapViewWidth: canvasWidth
        )
        return RouteMapOverlayMetrics.imageByCroppingAttributionStrip(
            from: image,
            stripHeight: stripHeight
        )
    }

    /// 설정에 따라 로고를 합성합니다. 저장 PNG는 로고 없이 두고 표시·공유 시점에 적용합니다.
    static func applyingBrandOverlay(to image: UIImage, style: HikingSnapshotStyle) -> UIImage {
        guard style.showsBrandLogo else { return image }
        let size = image.size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
            drawBrandLogo(in: context.cgContext, size: size)
        }
    }

    private protocol MapCoordinateProjecting {
        func point(for coordinate: CLLocationCoordinate2D) -> CGPoint
    }

    private struct ClosureCoordinateProjector: MapCoordinateProjecting {
        let project: (CLLocationCoordinate2D) -> CGPoint

        func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
            project(coordinate)
        }
    }

    private struct SnapshotCoordinateProjector: MapCoordinateProjecting {
        let snapshot: MKMapSnapshotter.Snapshot

        func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
            snapshot.point(for: coordinate)
        }
    }

    /// 하단 표기 스트립을 잘랐을 때 스냅샷 좌표를 캔버스 높이에 맞게 보정합니다.
    private struct CroppedSnapshotCoordinateProjector: MapCoordinateProjecting {
        let snapshot: MKMapSnapshotter.Snapshot
        let stripHeight: CGFloat

        func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
            let point = snapshot.point(for: coordinate)
            let fullHeight = snapshot.image.size.height
            let contentHeight = max(fullHeight - stripHeight, 1)
            let scaleY = fullHeight / contentHeight
            return CGPoint(x: point.x, y: point.y * scaleY)
        }
    }

    private struct RegionCoordinateProjector: MapCoordinateProjecting {
        let region: MKCoordinateRegion
        let canvasSize: CGSize

        func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
            HikingMapRegion.point(for: coordinate, in: region, canvasSize: canvasSize)
        }
    }

    /// 상세 `MapPolyline`과 동일한 경로 스타일.
    private static let detailRouteLineWidth: CGFloat = 5
    private static let detailEndpointOuterDiameter: CGFloat = 17
    private static let detailEndpointInnerDiameter: CGFloat = 11

    private static func drawRoute(
        using projector: MapCoordinateProjecting,
        coordinates: [CLLocationCoordinate2D],
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        let path = UIBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        for (index, coordinate) in coordinates.enumerated() {
            let point = projector.point(for: coordinate)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.lineWidth = detailRouteLineWidth * contentScale
        UIColor(red: 0.12, green: 0.72, blue: 0.45, alpha: 1).setStroke()
        path.stroke()
    }

    private static func drawEndpoints(
        using projector: MapCoordinateProjecting,
        coordinates: [CLLocationCoordinate2D],
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        guard let start = coordinates.first, let end = coordinates.last else { return }
        drawEndpoint(
            at: projector.point(for: start),
            fill: UIColor(red: 0.12, green: 0.72, blue: 0.45, alpha: 1),
            contentScale: contentScale,
            in: cgContext
        )
        drawEndpoint(
            at: projector.point(for: end),
            fill: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1),
            contentScale: contentScale,
            in: cgContext
        )
    }

    private static func drawEndpoint(
        at point: CGPoint,
        fill: UIColor,
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        let outerDiameter = detailEndpointOuterDiameter * contentScale
        let innerDiameter = detailEndpointInnerDiameter * contentScale
        let outerOrigin = outerDiameter / 2
        let innerInset = (outerDiameter - innerDiameter) / 2
        let outer = CGRect(
            x: point.x - outerOrigin,
            y: point.y - outerOrigin,
            width: outerDiameter,
            height: outerDiameter
        )
        cgContext.setFillColor(UIColor.white.cgColor)
        cgContext.fillEllipse(in: outer)
        cgContext.setFillColor(fill.cgColor)
        cgContext.fillEllipse(in: outer.insetBy(dx: innerInset, dy: innerInset))
    }

    private static func summits(for record: SavedHikingSession) -> [MountainSummit] {
        if let cached = record.session.nearbySummits, !cached.isEmpty {
            return cached
        }
        let coordinates = HikingSessionMetrics.resolvedDisplayRouteCoordinates(from: record.session)
        return MountainSummitRouteFilter.summits(near: coordinates)
    }

    private static func drawSummitMarkers(
        using projector: MapCoordinateProjecting,
        record: SavedHikingSession,
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        for summit in summits(for: record) {
            RouteSummitMarkerDrawing.drawMarker(
                name: summit.displayName,
                at: projector.point(for: summit.coordinate),
                contentScale: contentScale,
                in: cgContext
            )
        }
    }

    private static func drawDistanceMarkers(
        using projector: MapCoordinateProjecting,
        points: [HikingPoint],
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        let markers = HikingSessionMetrics.kilometerMarkerPlacements(from: points)
        for marker in markers {
            let routePoint = projector.point(for: marker.coordinate)
            RouteKilometerMarkerDrawing.drawMarker(
                label: marker.labelText,
                routePoint: routePoint,
                placesLabelOnLeadingSide: marker.placesLabelOnLeadingSide,
                contentScale: contentScale,
                in: cgContext
            )
        }
    }

    private static func drawPhotoMarkers(
        using projector: MapCoordinateProjecting,
        photos: [HikingTrailPhoto],
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        let placements = TrailPhotoMapMarkerPlacementBuilder.placements(for: photos)
        let clusterRadius = TrailPhotoMarkerMetrics.clusterRadius * contentScale

        for placement in placements {
            let anchor = projector.point(for: placement.coordinate)

            if placement.isCluster {
                for (index, _) in placement.photos.enumerated() {
                    let angle = Double(index) / Double(placement.photos.count) * 360
                    let radians = angle * .pi / 180
                    let tip = CGPoint(
                        x: anchor.x + CGFloat(sin(radians)) * clusterRadius,
                        y: anchor.y - CGFloat(cos(radians)) * clusterRadius
                    )
                    let rotation = CGFloat(atan2(-sin(radians), cos(radians)) * 180 / .pi)
                    TrailPhotoMarkerDrawing.drawPin(
                        tip: tip,
                        rotationDegrees: rotation,
                        in: cgContext,
                        contentScale: contentScale
                    )
                }
            } else {
                TrailPhotoMarkerDrawing.drawPin(
                    tip: anchor,
                    rotationDegrees: 0,
                    in: cgContext,
                    contentScale: contentScale
                )
            }
        }
    }

    private static func drawPinnedThumbnails(
        record: SavedHikingSession,
        photos: [HikingTrailPhoto],
        contentScale: CGFloat,
        in cgContext: CGContext,
        canvasSize: CGSize
    ) {
        let size = 64 * contentScale
        let ring = 5 * contentScale
        let spacing = 7 * contentScale
        let topPadding = 16 * contentScale
        let shadowBleed = 8 * contentScale
        let outerDiameter = size + ring * 2
        let totalWidth = CGFloat(photos.count) * outerDiameter + CGFloat(max(photos.count - 1, 0)) * spacing
        var x = (canvasSize.width - totalWidth) / 2
        let y = topPadding + shadowBleed

        for photo in photos {
            let frame = CGRect(x: x, y: y, width: outerDiameter, height: outerDiameter)
            drawPinnedThumbnailChip(
                record: record,
                photo: photo,
                in: frame,
                imageDiameter: size,
                ringWidth: ring,
                contentScale: contentScale,
                in: cgContext
            )
            x += outerDiameter + spacing
        }
    }

    private static func drawPinnedThumbnailChip(
        record: SavedHikingSession,
        photo: HikingTrailPhoto,
        in frame: CGRect,
        imageDiameter: CGFloat,
        ringWidth: CGFloat,
        contentScale: CGFloat,
        in cgContext: CGContext
    ) {
        let center = CGPoint(x: frame.midX, y: frame.midY)

        cgContext.saveGState()
        cgContext.setShadow(
            offset: CGSize(width: 0, height: 3 * contentScale),
            blur: 8 * contentScale,
            color: UIColor.black.withAlphaComponent(0.22).cgColor
        )
        cgContext.setFillColor(UIColor.white.withAlphaComponent(0.38).cgColor)
        cgContext.fillEllipse(in: frame)
        cgContext.restoreGState()

        cgContext.setStrokeColor(UIColor.black.withAlphaComponent(0.12).cgColor)
        cgContext.setLineWidth(1)
        cgContext.strokeEllipse(in: frame)

        let imageRect = CGRect(
            x: center.x - imageDiameter / 2,
            y: center.y - imageDiameter / 2,
            width: imageDiameter,
            height: imageDiameter
        )

        if let image = HikingTrailPhotoStore.loadImage(sessionID: record.id, filename: photo.filename) {
            cgContext.saveGState()
            UIBezierPath(ovalIn: imageRect).addClip()
            image.draw(in: imageRect)
            cgContext.restoreGState()
        } else {
            cgContext.setFillColor(UIColor.tertiarySystemFill.cgColor)
            cgContext.fillEllipse(in: imageRect)
        }

        cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.85).cgColor)
        cgContext.setLineWidth(2 * contentScale)
        cgContext.strokeEllipse(in: imageRect.insetBy(dx: 1, dy: 1))
    }

    private static func drawBrandLogo(in cgContext: CGContext, size: CGSize) {
        let layout = RouteBrandLogoMetrics.layout(forCanvasWidth: size.width)
        let layoutScale = size.width / RouteBrandLogoMetrics.referenceCanvasWidth
        let logoRect = CGRect(
            x: layout.leading,
            y: size.height - layout.bottom - layout.side,
            width: layout.side,
            height: layout.side
        )
        guard let logo = BrandLogoImage.rasterizedLogo(side: layout.side) else { return }

        cgContext.saveGState()
        cgContext.setShadow(
            offset: CGSize(width: 0, height: 2 * layoutScale),
            blur: 8 * layoutScale,
            color: UIColor.black.withAlphaComponent(0.18).cgColor
        )
        logo.draw(in: logoRect)
        cgContext.restoreGState()
    }
}

#endif
