//
//  HikingRouteSnapshotGenerator.swift
//  Shared
//

#if os(iOS)

import CoreImage
import CoreLocation
import MapKit
import UIKit

enum HikingRouteSnapshotAppearance {
    /// 상세·썸네일·기록 카드 — 기존 스타일.
    case standard
    /// 공유 요약 A안 — 회색 지도, 흰 외곽선 초록 경로, 합친 km 라벨, 끝점 잉크.
    case shareSummary
    /// Simple Color — 컬러 지도(프리-그레이), 동일 레이아웃·경로·km 규칙.
    case shareSummaryColor

    /// Share-summary layout family (grey or color): top-aligned fit, km clamps, route chrome.
    var usesShareSummaryChrome: Bool {
        switch self {
        case .shareSummary, .shareSummaryColor: true
        case .standard: false
        }
    }

    /// Greyscale paper-tone remapping + solid map-paper fade.
    var usesGreyMapTone: Bool {
        self == .shareSummary
    }
}

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
    /// Legacy detail layout width (card chrome). Label scale no longer uses this —
    /// km pills share Simple’s 430pt design space (`RouteKilometerMarkerMetrics.labelDesignCanvasWidth`).
    private static let mapLayoutReferenceWidth: CGFloat = 377
    private static let snapshotScale: CGFloat = 2
    /// 시작·종료·일시정지 점. Android 경로 지도와 같은 색입니다.
    private static let startPointColor = UIColor(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0, alpha: 1)
    private static let endPointColor = UIColor(red: 255.0 / 255.0, green: 59.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)

    /// Km/route overlay scale — same Simple SoT (`width/430`) for detail, Data Card, and Simple.
    private static func mapContentScale(for canvasWidth: CGFloat, appearance: HikingRouteSnapshotAppearance) -> CGFloat {
        _ = appearance
        return RouteKilometerMarkerMetrics.labelContentScale(forWidth: canvasWidth)
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
        let contentScale = mapContentScale(for: canvasSize.width, appearance: .standard)
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

            if needsSummitOverlays(record: record) {
                drawSummitMarkers(
                    using: projector,
                    record: record,
                    contentScale: contentScale,
                    in: context.cgContext
                )
            }

            if mapOptions.showsDistanceMarkers || mapOptions.showsTimeMarkers {
                drawKilometerMarkers(
                    using: projector,
                    record: record,
                    coordinates: coordinates,
                    showsDistance: mapOptions.showsDistanceMarkers,
                    showsTime: mapOptions.showsTimeMarkers,
                    contentScale: contentScale,
                    appearance: .standard,
                    canvasSize: canvasSize,
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
        (mapOptions.showsDistanceMarkers || mapOptions.showsTimeMarkers)
            && !HikingSessionMetrics.kilometerMarkerPlacements(from: record.session.points).isEmpty
    }

    /// 직전 `generate`가 상세 화면 지도를 찍어 산산 로고까지 포함했는지.
    private static var captureIncludesOnScreenLogo = false

    static func consumeCaptureIncludesOnScreenLogo() -> Bool {
        let included = captureIncludesOnScreenLogo
        captureIncludesOnScreenLogo = false
        return included
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
        captureIncludesOnScreenLogo = false
        let targetCanvas = canvasSize ?? routeImageSize
        // 목록 썸네일은 정사각형 안에 경로 전체를 맞춥니다. 상세 이미지는 상세 지도 크기를 씁니다.
        let captureMapSize = listThumbnailOnly ? targetCanvas : HikingRouteImageLayout.captureSize
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
            captureIncludesOnScreenLogo = base.includesLiveDetailContent
            return composite(
                baseImage: base.image,
                projector: projector,
                record: record,
                coordinates: coordinates,
                canvasSize: liveCanvas,
                pixelScale: scale,
                mapOptions: mapOptions,
                includesLiveDetailContent: base.includesLiveDetailContent,
                listThumbnailOnly: listThumbnailOnly
            )
        }

        return await captureWithSnapshotter(
            record: record,
            coordinates: coordinates,
            fittingCoordinates: fittingCoordinates,
            canvasSize: targetCanvas,
            pixelScale: scale,
            mapOptions: mapOptions,
            reservesLegalAttributionStrip: reservesLegalAttributionStrip,
            listThumbnailOnly: listThumbnailOnly
        )
    }

    /// 요약 저장용. 메모 하단부터 카드 상단까지, 경로의 긴 축이 그 영역에 닿게 맞춥니다.
    @MainActor
    static func fittedMapImage(
        record: SavedHikingSession,
        canvasSize: CGSize,
        pixelScale: CGFloat,
        mapOptions: HikingShareMapExportOptions,
        insetTop: CGFloat = 0,
        insetBottom: CGFloat = 0,
        insetLeft: CGFloat = 0,
        insetRight: CGFloat = 0,
        routeFillFraction: CGFloat = 1,
        appearance: HikingRouteSnapshotAppearance = .standard,
        fadeSolidEndY: CGFloat? = nil
    ) async -> UIImage? {
        let coordinates = HikingSessionMetrics.resolvedDisplayRouteCoordinates(from: record.session)
        guard coordinates.count >= 2 else { return nil }
        return await captureWithSnapshotter(
            record: record,
            coordinates: coordinates,
            fittingCoordinates: coordinates,
            canvasSize: canvasSize,
            pixelScale: pixelScale,
            mapOptions: mapOptions,
            reservesLegalAttributionStrip: false,
            insetTop: insetTop,
            insetBottom: insetBottom,
            insetLeft: insetLeft,
            insetRight: insetRight,
            routeFillFraction: routeFillFraction,
            appearance: appearance,
            fadeSolidEndY: fadeSolidEndY
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
        reservesLegalAttributionStrip: Bool,
        insetTop: CGFloat = 0,
        insetBottom: CGFloat = 0,
        insetLeft: CGFloat = 0,
        insetRight: CGFloat = 0,
        routeFillFraction: CGFloat = HikingRouteImageLayout.routeCardFillFraction,
        listThumbnailOnly: Bool = false,
        appearance: HikingRouteSnapshotAppearance = .standard,
        fadeSolidEndY: CGFloat? = nil
    ) async -> UIImage? {
        // MKMapSnapshotter 이미지에는 Apple 법적 표기·로고가 포함되지 않습니다(개발자가 직접
        // 그려야 함). 따라서 strip 크롭은 실제 지도를 잘라내 경로를 어긋나게 할 뿐이라 하지 않습니다.
        let snapshotCanvas = canvasSize

        let options = MKMapSnapshotter.Options()
        options.region = HikingMapRegion.fitting(
            coordinates: fittingCoordinates,
            viewSize: snapshotCanvas,
            insetTop: insetTop,
            insetLeft: insetLeft,
            insetBottom: insetBottom,
            insetRight: insetRight,
            routeFillFraction: routeFillFraction,
            // Share summary: hug headerBottom+clearance when the route is width-limited (memo-none).
            verticalAlign: appearance.usesShareSummaryChrome ? .top : .center
        )
        options.size = snapshotCanvas
        options.scale = pixelScale
        options.preferredConfiguration = appearance.usesGreyMapTone
            ? HikingMapCaptureConfiguration.shareSummaryMuted
            : HikingMapCaptureConfiguration.standard
        let interfaceStyle: UIUserInterfaceStyle = appearance.usesShareSummaryChrome
            ? .light
            : AppExportAppearance.resolvedUserInterfaceStyle()
        options.traitCollection = UITraitCollection(userInterfaceStyle: interfaceStyle)

        return await withCheckedContinuation { continuation in
            MKMapSnapshotter(options: options).start { snapshot, error in
                guard let snapshot, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }

                let projector = SnapshotCoordinateProjector(snapshot: snapshot)
                let baseImage: UIImage
                if appearance.usesGreyMapTone {
                    baseImage = shareSummaryTonedMapImage(snapshot.image) ?? snapshot.image
                } else {
                    baseImage = snapshot.image
                }
                let image = composite(
                    baseImage: baseImage,
                    projector: projector,
                    record: record,
                    coordinates: coordinates,
                    canvasSize: canvasSize,
                    pixelScale: pixelScale,
                    mapOptions: mapOptions,
                    listThumbnailOnly: listThumbnailOnly,
                    appearance: appearance,
                    fadeSolidEndY: fadeSolidEndY
                )
                continuation.resume(returning: image)
            }
        }
    }

    private static func drawShareSummaryPaperFade(
        solidEndY: CGFloat,
        canvasSize: CGSize,
        in cgContext: CGContext
    ) {
        let fadeEnd = min(solidEndY + ShareSummaryTokens.fadeTail, canvasSize.height)
        let colors = [
            ShareSummaryTokens.mapPaperUIColor.withAlphaComponent(ShareSummaryTokens.fadeSolidOpacity).cgColor,
            ShareSummaryTokens.mapPaperUIColor.withAlphaComponent(ShareSummaryTokens.fadeSolidOpacity).cgColor,
            ShareSummaryTokens.mapPaperUIColor.withAlphaComponent(0).cgColor
        ] as CFArray
        let locations: [CGFloat] = [
            0,
            max(solidEndY / canvasSize.height, 0),
            min(fadeEnd / canvasSize.height, 1)
        ]
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: locations
        ) else { return }
        cgContext.saveGState()
        cgContext.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: canvasSize.height),
            options: []
        )
        cgContext.restoreGState()
    }

    /// Soft white → clear so logo/title stay readable while color map shows through.
    private static func drawShareSummaryColorTitleBlend(
        solidEndY: CGFloat,
        canvasSize: CGSize,
        in cgContext: CGContext
    ) {
        let fadeEnd = min(solidEndY + ShareSummaryTokens.fadeTail, canvasSize.height)
        let colors = [
            UIColor.white.withAlphaComponent(0.72).cgColor,
            UIColor.white.withAlphaComponent(0.42).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor
        ] as CFArray
        let locations: [CGFloat] = [
            0,
            max(solidEndY / canvasSize.height, 0),
            min(fadeEnd / canvasSize.height, 1)
        ]
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: locations
        ) else { return }
        cgContext.saveGState()
        cgContext.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: canvasSize.height),
            options: []
        )
        cgContext.restoreGState()
    }

    /// Warm Simple Grey: paper #E6E2E0; roads → #EEEBE9; water → #D9D3D0; labels → #8B8B8E.
    /// Apple MKMapSnapshotter cannot recolor style paints — luminance/hue→warm RGB remap is the
    /// style-equivalent path (no overlay/multiply). Title-bg / paper / roads unchanged.
    private static func shareSummaryTonedMapImage(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Warm chromatic targets — #E6E2E0 / #EEEBE9 / #D9D3D0 / #8B8B8E.
        let labelR = 139.0, labelG = 139.0, labelB = 142.0
        let paperR = 230.0, paperG = 226.0, paperB = 224.0
        let roadR = 238.0, roadG = 235.0, roadB = 233.0
        let waterR = 217.0, waterG = 211.0, waterB = 208.0 // #D9D3D0
        let count = width * height
        for i in 0..<count {
            let o = i * bytesPerPixel
            let r = Double(pixels[o])
            let g = Double(pixels[o + 1])
            let b = Double(pixels[o + 2])
            let y = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            // Muted Apple water reads cooler/bluer than land before flatten.
            let coolBlue = (b > r + 6) && (b >= g - 2) && (y >= 0.42) && (y <= 0.92)
            let outR: Double
            let outG: Double
            let outB: Double
            if y < 0.40 {
                // Labels / dark features → mapLabel band (keep some contrast).
                let t = 0.75 + 0.25 * (y / 0.40)
                outR = labelR * t
                outG = labelG * t
                outB = labelB * t
            } else if y > 0.985 {
                outR = roadR
                outG = roadG
                outB = roadB
            } else if coolBlue {
                outR = waterR
                outG = waterG
                outB = waterB
            } else {
                // Flat warm paper #E6E2E0; near-white roads stay in y>0.985 → #EEEBE9.
                outR = paperR
                outG = paperG
                outB = paperB
            }
            pixels[o] = UInt8(max(0, min(255, outR.rounded())))
            pixels[o + 1] = UInt8(max(0, min(255, outG.rounded())))
            pixels[o + 2] = UInt8(max(0, min(255, outB.rounded())))
        }
        guard let outImage = ctx.makeImage() else { return nil }
        return UIImage(cgImage: outImage, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func composite(
        baseImage: UIImage,
        projector: MapCoordinateProjecting,
        record: SavedHikingSession,
        coordinates: [CLLocationCoordinate2D],
        canvasSize: CGSize,
        pixelScale: CGFloat,
        mapOptions: HikingShareMapExportOptions,
        includesLiveDetailContent: Bool = false,
        listThumbnailOnly: Bool = false,
        appearance: HikingRouteSnapshotAppearance = .standard,
        fadeSolidEndY: CGFloat? = nil
    ) -> UIImage {
        let contentScale = mapContentScale(for: canvasSize.width, appearance: appearance)
        let format = UIGraphicsImageRendererFormat()
        format.scale = pixelScale
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        // Simple Color: heal bottom-leading gutter under the floating card (legal/dim plate
        // read as a dark grey rectangle beside the rounded corner). No solid fill.
        let mapLayer: UIImage = appearance == .shareSummaryColor
            ? RouteMapOverlayMetrics.coveringShareSummaryColorCardGutter(on: baseImage)
            : baseImage

        return renderer.image { context in
            if appearance.usesGreyMapTone {
                ShareSummaryTokens.mapPaperUIColor.setFill()
                context.fill(CGRect(origin: .zero, size: canvasSize))
            }
            mapLayer.draw(in: CGRect(origin: .zero, size: canvasSize))

            // JW 18:25 — MKMapSnapshotter may still bake /Legal at bottom-left; keep only the
            // hand-drawn 「지도」 between map and card. Cover with map paper (not white).
            if appearance.usesGreyMapTone {
                ShareSummaryTokens.mapPaperUIColor.setFill()
                context.fill(
                    RouteMapOverlayMetrics.nativeAttributionMaskRect(forCanvasSize: canvasSize)
                )
            }

            // Layer order (finding 2): map → fade → route → markers → labels.
            if appearance.usesGreyMapTone, let solidEnd = fadeSolidEndY, solidEnd > 0 {
                drawShareSummaryPaperFade(
                    solidEndY: solidEnd,
                    canvasSize: canvasSize,
                    in: context.cgContext
                )
            } else if appearance == .shareSummaryColor, let solidEnd = fadeSolidEndY, solidEnd > 0 {
                drawShareSummaryColorTitleBlend(
                    solidEndY: solidEnd,
                    canvasSize: canvasSize,
                    in: context.cgContext
                )
            }

            if !includesLiveDetailContent {
                // Route + short cross bridges first; km markers / labels always on top
                // (Android decorateSummaryMap: drawShareRoute → endpoints → label blits).
                // No punch holes (they break rails). Marker centers only trim bridge ends.
                drawRoute(
                    using: projector,
                    coordinates: coordinates,
                    contentScale: contentScale,
                    appearance: appearance,
                    in: context.cgContext
                )
            }

            // 목록 썸네일은 지도와 경로 선만 남깁니다.
            if listThumbnailOnly {
                return
            }

            // Live detail tiles already include the route stroke/endpoints, but not
            // export km capsules. Still bake distance/time labels when options ask
            // (Data Card must match Android detail blue labels).
            if includesLiveDetailContent {
                if mapOptions.showsDistanceMarkers || mapOptions.showsTimeMarkers {
                    drawKilometerMarkers(
                        using: projector,
                        record: record,
                        coordinates: coordinates,
                        showsDistance: mapOptions.showsDistanceMarkers,
                        showsTime: mapOptions.showsTimeMarkers,
                        contentScale: contentScale,
                        appearance: appearance,
                        canvasSize: canvasSize,
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
                return
            }

            if mapOptions.showsPhotoMarkers {
                drawPhotoMarkers(
                    using: projector,
                    photos: record.session.photos,
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

            if mapOptions.showsDistanceMarkers || mapOptions.showsTimeMarkers {
                drawKilometerMarkers(
                    using: projector,
                    record: record,
                    coordinates: coordinates,
                    showsDistance: mapOptions.showsDistanceMarkers,
                    showsTime: mapOptions.showsTimeMarkers,
                    contentScale: contentScale,
                    appearance: appearance,
                    canvasSize: canvasSize,
                    in: context.cgContext
                )
            }

            drawEndpoints(
                using: projector,
                coordinates: coordinates,
                contentScale: contentScale,
                appearance: appearance,
                in: context.cgContext
            )

            if !appearance.usesShareSummaryChrome,
               mapOptions.showsPinnedThumbnails,
               !record.mapPinnedPhotos.isEmpty {
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
        appearance: HikingRouteSnapshotAppearance,
        in cgContext: CGContext
    ) {
        let points = coordinates.map { projector.point(for: $0) }
        guard points.count >= 2 else { return }

        switch appearance {
        case .standard:
            // Detail snapshot: continuous green + white→green overlay only at true crosses
            // (same rule as live detail map / share summary).
            drawContinuousRouteWithCrossOverlays(
                points: points,
                contentScale: contentScale,
                casingWidth: detailRouteLineWidth * 1.6 * contentScale,
                fillWidth: detailRouteLineWidth * contentScale,
                white: UIColor.white.withAlphaComponent(0.9),
                green: UIColor(red: 0.12, green: 0.72, blue: 0.45, alpha: 1),
                shadow: false,
                forceChunks: false,
                in: cgContext
            )
        case .shareSummary, .shareSummaryColor:
            // JW/팀장: continuous Path (white→green, no join seams) + local white→green
            // overlay only at true self-crossings. No gray shadow on AFTER.
            // `-SANSAN_ROUTE_CHUNKS` exports the old chunk before for compare captures.
            let forceChunks = ProcessInfo.processInfo.arguments.contains("-SANSAN_ROUTE_CHUNKS")
                || ProcessInfo.processInfo.environment["SANSAN_ROUTE_CHUNKS"] == "1"
            drawContinuousRouteWithCrossOverlays(
                points: points,
                contentScale: contentScale,
                casingWidth: ShareSummaryTokens.routeCasing * contentScale,
                fillWidth: ShareSummaryTokens.routeWidth * contentScale,
                white: .white,
                green: ShareSummaryTokens.accentUIColor,
                shadow: false,
                forceChunks: forceChunks,
                in: cgContext
            )
        }
    }

    /// Continuous white→green ribbon + later-suffix overlay at true crosses.
    /// `forceChunks` restores chronological short chunks (join seams) for before captures.
    private static func drawContinuousRouteWithCrossOverlays(
        points: [CGPoint],
        contentScale: CGFloat,
        casingWidth: CGFloat,
        fillWidth: CGFloat,
        white: UIColor,
        green: UIColor,
        shadow: Bool,
        forceChunks: Bool,
        in cgContext: CGContext
    ) {
        guard points.count >= 2 else { return }

        // Never leave a stale CG shadow on the context (share-summary AFTER must be shadow-free).
        cgContext.setShadow(offset: .zero, blur: 0, color: nil)

        func strokeWhiteThenGreen(_ path: UIBezierPath, withShadow: Bool) {
            cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            if withShadow {
                // Legacy chunk-before only — AFTER passes withShadow: false.
                cgContext.saveGState()
                cgContext.setShadow(
                    offset: CGSize(width: 0, height: 1 * contentScale),
                    blur: 1.2 * contentScale,
                    color: ShareSummaryTokens.inkUIColor.withAlphaComponent(0.18).cgColor
                )
                path.lineWidth = casingWidth
                white.setStroke()
                path.stroke()
                cgContext.restoreGState()
                cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            } else {
                // Android 6a62d1e: one continuous Path stroke. White AA-off (AA vs map =
                // gray halo); green AA-on. SRC_OVER — never .copy.
                cgContext.saveGState()
                cgContext.setShadow(offset: .zero, blur: 0, color: nil)
                cgContext.setBlendMode(.normal)
                // Continuous dual rails: AA-on white + green over one path (single stroke each).
                cgContext.setShouldAntialias(true)
                cgContext.setAllowsAntialiasing(true)
                path.lineWidth = casingWidth
                white.setStroke()
                path.stroke()
                path.lineWidth = fillWidth
                green.setStroke()
                path.stroke()
                cgContext.restoreGState()
                cgContext.setShadow(offset: .zero, blur: 0, color: nil)
                return
            }
            path.lineWidth = fillWidth
            green.setStroke()
            path.stroke()
            cgContext.setShadow(offset: .zero, blur: 0, color: nil)
        }

        if forceChunks {
            // Legacy chronological chunks — later white→green stacks at joins/crosses.
            let maxChunkPx: CGFloat = 28 * contentScale
            let maxVerticesPerChunk = 12
            var startIdx = 0
            var isFirst = true
            while startIdx < points.count - 1 {
                var endIdx = startIdx + 1
                var traveled: CGFloat = 0
                while endIdx < points.count - 1 && traveled < maxChunkPx {
                    let dx = points[endIdx + 1].x - points[endIdx].x
                    let dy = points[endIdx + 1].y - points[endIdx].y
                    traveled += hypot(dx, dy)
                    endIdx += 1
                    if endIdx - startIdx >= maxVerticesPerChunk { break }
                }
                if endIdx <= startIdx {
                    endIdx = min(points.count - 1, startIdx + 1)
                }
                let path = UIBezierPath()
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.move(to: points[startIdx])
                for index in (startIdx + 1)...endIdx {
                    path.addLine(to: points[index])
                }
                strokeWhiteThenGreen(path, withShadow: shadow && isFirst)
                isFirst = false
                if endIdx >= points.count - 1 { break }
                startIdx = endIdx
            }
            return
        }

        // Android 6a62d1e drawShareRoute — same algorithm:
        // detect crosses on RAW; stroke continuous BASE on cleaned (one Path);
        // bridge = short later piece around the hit, ONE path stroke (not stitched
        // micro-polylines). Length casing×1.75 / ×2.35; white butt AA-off; green round AA-on.
        let rawPoints = points
        let drawPoints = RouteSelfCrossing.cleanedPoints(rawPoints)
        guard drawPoints.count >= 2 else { return }

        let minLoopLength = max(casingWidth * 8, 48 * contentScale)
        let whiteHalf = casingWidth * 1.75
        let greenHalf = casingWidth * 2.35
        let bridgeCasing = casingWidth
        let bridgeFill = fillWidth

        // Android jMin = i+2. False joint seams are filtered by proximity |sin|≥0.28
        // + soft interior (RouteSelfCrossing), not by raising separation.
        var bridgeSource = rawPoints
        var hits = RouteSelfCrossing.hits(
            in: rawPoints,
            minLoopLength: minLoopLength,
            minSeparationEdges: 2,
            minCrossSin: 0.20,
            minProximitySin: 0.28,
            dedupeDistance: max(casingWidth * 2.0, minLoopLength * 0.2),
            proximityDistance: casingWidth * 0.65
        )
        if hits.isEmpty {
            bridgeSource = drawPoints
            hits = RouteSelfCrossing.hits(
                in: drawPoints,
                minLoopLength: minLoopLength,
                minSeparationEdges: 2,
                minCrossSin: 0.20,
                minProximitySin: 0.28,
                dedupeDistance: max(casingWidth * 2.0, minLoopLength * 0.2),
                proximityDistance: casingWidth * 0.65
            )
        }
        #if DEBUG
        NSLog(
            "[km-label] route crosses unique=%d raw=%d clean=%d whiteHalf=%.1f casing/fill=%.2f/%.2f",
            hits.count, rawPoints.count, drawPoints.count, whiteHalf, bridgeCasing, bridgeFill
        )
        for hit in hits {
            NSLog(
                "[km-label] cross at (%.1f,%.1f) laterEdge=%d u=%.3f",
                hit.point.x, hit.point.y, hit.laterEdge, hit.u
            )
        }
        #endif

        // Base: one continuous path stroke (Android pathOf + drawPath×2).
        // Catmull-Rom→cubic so CG joins aren't 톱니·조각; still a single Path.stroke.
        let strokePoints = Self.simplifiedBridgePoints(
            drawPoints,
            epsilon: max(0.55 * contentScale, 0.4)
        )
        let full = Self.continuousStrokePath(strokePoints)
        full.lineCapStyle = .round
        full.lineJoinStyle = .round
        strokeWhiteThenGreen(full, withShadow: shadow)

        // Bridge: Android shareRoutePointsAround → pathFromPoints → single drawPath.
        // One UIBezierPath.stroke per layer — never stroke segment-by-segment (조각 레일).
        for hit in hits {
            let whitePts = Self.simplifiedBridgePoints(
                RouteSelfCrossing.overlayPoints(
                    drawPoints: bridgeSource,
                    hit: hit,
                    backPad: whiteHalf,
                    forwardPad: whiteHalf
                ),
                epsilon: max(0.7 * contentScale, 0.5)
            )
            let greenPts = Self.simplifiedBridgePoints(
                RouteSelfCrossing.overlayPoints(
                    drawPoints: bridgeSource,
                    hit: hit,
                    backPad: greenHalf,
                    forwardPad: greenHalf
                ),
                epsilon: max(0.7 * contentScale, 0.5)
            )
            guard whitePts.count >= 2, greenPts.count >= 2 else { continue }

            func strokeBridge(_ pts: [CGPoint], width: CGFloat, color: UIColor, cap: CGLineCap, antialias: Bool) {
                let path = Self.continuousStrokePath(pts)
                path.lineWidth = width
                path.lineCapStyle = cap
                path.lineJoinStyle = .round
                cgContext.saveGState()
                cgContext.setShadow(offset: .zero, blur: 0, color: nil)
                cgContext.setBlendMode(.normal)
                cgContext.setShouldAntialias(antialias)
                cgContext.setAllowsAntialiasing(antialias)
                color.setStroke()
                path.stroke() // single continuous stroke
                cgContext.restoreGState()
            }

            // One continuous path each: white butt then longer green round (Android order).
            // AA-on so bridge rails stay continuous with the base (no 톱니 at joins).
            strokeBridge(whitePts, width: bridgeCasing, color: white, cap: .butt, antialias: true)
            strokeBridge(greenPts, width: bridgeFill, color: green, cap: .round, antialias: true)

            cgContext.setShadow(offset: .zero, blur: 0, color: nil)

            #if DEBUG
            var polyLen: CGFloat = 0
            for i in 0..<(whitePts.count - 1) {
                polyLen += hypot(whitePts[i + 1].x - whitePts[i].x, whitePts[i + 1].y - whitePts[i].y)
            }
            NSLog(
                "[km-label] bridge at (%.1f,%.1f) pts=%d len=%.1f half=%.1f/%.1f w=%.2f/%.2f",
                hit.point.x, hit.point.y, whitePts.count, polyLen,
                whiteHalf, greenHalf, bridgeCasing, bridgeFill
            )
            #endif
        }
    }

    /// Single continuous stroke path: Catmull-Rom → cubics (no polyline join teeth).
    private static func continuousStrokePath(_ points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        guard points.count >= 2 else { return path }
        path.move(to: points[0])
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(points.count - 1, i + 2)]
            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, controlPoint1: cp1, controlPoint2: cp2)
        }
        return path
    }

    /// Drop GPS micro-wiggles on a short bridge while keeping endpoints + shape (one path).
    private static func simplifiedBridgePoints(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2, epsilon > 0 else { return points }
        func perpDist(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            if len2 < 1e-8 { return hypot(p.x - a.x, p.y - a.y) }
            return abs((p.x - a.x) * dy - (p.y - a.y) * dx) / sqrt(len2)
        }
        func douglas(_ pts: [CGPoint]) -> [CGPoint] {
            guard pts.count > 2 else { return pts }
            var maxD: CGFloat = 0
            var idx = 0
            let a = pts[0], b = pts[pts.count - 1]
            for i in 1..<(pts.count - 1) {
                let d = perpDist(pts[i], a, b)
                if d > maxD { maxD = d; idx = i }
            }
            if maxD <= epsilon {
                return [a, b]
            }
            let left = douglas(Array(pts[0...idx]))
            let right = douglas(Array(pts[idx...]))
            return left.dropLast() + right
        }
        let simplified = douglas(points)
        return simplified.count >= 2 ? simplified : points
    }

    private static func drawEndpoints(
        using projector: MapCoordinateProjecting,
        coordinates: [CLLocationCoordinate2D],
        contentScale: CGFloat,
        appearance: HikingRouteSnapshotAppearance,
        in cgContext: CGContext
    ) {
        guard let start = coordinates.first, let end = coordinates.last else { return }
        let outer: CGFloat
        let inner: CGFloat
        let endFill: UIColor
        switch appearance {
        case .standard:
            outer = detailEndpointOuterDiameter
            inner = detailEndpointInnerDiameter
            endFill = endPointColor
        case .shareSummary, .shareSummaryColor:
            outer = ShareSummaryTokens.markerOuter
            inner = ShareSummaryTokens.markerInner
            endFill = ShareSummaryTokens.inkUIColor
        }
        drawEndpoint(
            at: projector.point(for: start),
            fill: startPointColor,
            outerDiameter: outer,
            innerDiameter: inner,
            contentScale: contentScale,
            appearance: appearance,
            in: cgContext
        )
        drawEndpoint(
            at: projector.point(for: end),
            fill: endFill,
            outerDiameter: outer,
            innerDiameter: inner,
            contentScale: contentScale,
            appearance: appearance,
            in: cgContext
        )
    }

    private static func drawEndpoint(
        at point: CGPoint,
        fill: UIColor,
        outerDiameter: CGFloat,
        innerDiameter: CGFloat,
        contentScale: CGFloat,
        appearance: HikingRouteSnapshotAppearance,
        in cgContext: CGContext
    ) {
        let scaledOuter = outerDiameter * contentScale
        let scaledInner = innerDiameter * contentScale
        let outerOrigin = scaledOuter / 2
        let innerInset = (scaledOuter - scaledInner) / 2
        let outer = CGRect(
            x: point.x - outerOrigin,
            y: point.y - outerOrigin,
            width: scaledOuter,
            height: scaledOuter
        )
        cgContext.saveGState()
        // Share-summary AFTER: no endpoint shadow (팀장 — 그림자 0).
        cgContext.setShadow(offset: .zero, blur: 0, color: nil)
        cgContext.setFillColor(UIColor.white.cgColor)
        cgContext.fillEllipse(in: outer)
        cgContext.restoreGState()
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

    private static func drawKilometerMarkers(
        using projector: MapCoordinateProjecting,
        record: SavedHikingSession,
        coordinates: [CLLocationCoordinate2D],
        showsDistance: Bool,
        showsTime: Bool,
        contentScale: CGFloat,
        appearance: HikingRouteSnapshotAppearance,
        canvasSize: CGSize,
        in cgContext: CGContext
    ) {
        let markers = HikingSessionMetrics.kilometerMarkerPlacements(from: record.session.points)
        let times = showsTime
            ? HikingSessionMetrics.kilometerArrivalElapsedLabels(
                from: record.session.points,
                startedAt: record.session.effectiveStartedAt,
                segmentBreaks: record.session.segmentBreaks
            )
            : [:]
        var endpoints: [CGPoint] = []
        if let start = coordinates.first {
            endpoints.append(projector.point(for: start))
        }
        if let end = coordinates.last, coordinates.count > 1 {
            endpoints.append(projector.point(for: end))
        }
        let requests: [RouteKilometerLabelRequest] = markers.compactMap { marker in
            let distance = showsDistance ? marker.labelText : nil
            let time = times[marker.kilometer]
            guard distance != nil || time != nil else { return nil }
            return RouteKilometerLabelRequest(
                kilometer: marker.kilometer,
                distanceLabel: distance,
                timeLabel: time,
                routePoint: projector.point(for: marker.coordinate),
                preferredLeadingSide: marker.placesLabelOnLeadingSide
            )
        }
        // Share-summary: white capsules + inset 24. Data Card / standard: detail blue
        // capsules (Android DetailKmLabelDrawable parity).
        let clampBounds = appearance.usesShareSummaryChrome
        let imageSize = canvasSize
        let sideInset = clampBounds
            ? ShareSummaryTokens.kmLabelBoundsInset * contentScale
            : RouteKilometerMarkerMetrics.detailLabelSideInset * contentScale
        let routePolyline = coordinates.map { projector.point(for: $0) }
        // Title(+memo) bottom → forbidden band for km labels (titleLabelMinGap).
        let titleBlockBottom: CGFloat? = {
            guard appearance.usesShareSummaryChrome else { return nil }
            let memoLines = ShareSummaryTokens.memoLineCount(record.memo, canvasWidth: canvasSize.width)
            return ShareSummaryTokens.headerBottom(memoLineCount: memoLines) * contentScale
        }()
        // Snapshot is offline — allow full search under the 300ms interactive budget.
        let previousBudget = RouteKilometerLabelPlacement.softTimeBudgetSeconds
        RouteKilometerLabelPlacement.softTimeBudgetSeconds = 2.0
        defer { RouteKilometerLabelPlacement.softTimeBudgetSeconds = previousBudget }
        var shifts: [Int: RouteKilometerLabelShift]
        if appearance.usesShareSummaryChrome {
            let placement = RouteKilometerLabelPlacement.placeSummary(
                markers: requests,
                endpointPoints: endpoints,
                routePolyline: routePolyline,
                contentScale: contentScale,
                imageSize: imageSize,
                sideInset: sideInset,
                pathHalfWidth: ShareSummaryTokens.routeCasing / 2,
                titleBlockBottom: titleBlockBottom
            )
            shifts = placement.shifts
            if shifts.isEmpty {
                shifts = RouteKilometerMarkerDrawing.labelShifts(
                    for: requests,
                    endpointPoints: endpoints,
                    contentScale: contentScale,
                    imageSize: imageSize,
                    sideInset: sideInset,
                    routePolyline: routePolyline,
                    titleBlockBottom: titleBlockBottom
                )
            }
        } else {
            let placement = RouteKilometerMarkerDrawing.thinnedDetailLabelShifts(
                for: requests,
                endpointPoints: endpoints,
                contentScale: contentScale,
                imageSize: imageSize,
                routePolyline: routePolyline,
                preferModeStep: 1,
                zoomDelta: 1
            )
            shifts = placement.shifts
            if shifts.isEmpty {
                shifts = RouteKilometerMarkerDrawing.labelShifts(
                    for: requests,
                    endpointPoints: endpoints,
                    contentScale: contentScale,
                    imageSize: imageSize,
                    sideInset: sideInset,
                    routePolyline: routePolyline,
                    pathHalfWidth: 4,
                    titleBlockBottom: nil
                )
            }
        }
        // Spec §6/§7: dots for every km; labels only where the solver placed a shift
        // (5km mode → non-multiples stay dot-only). Never invent fallback label offsets.
        let useDetailBlue = !appearance.usesShareSummaryChrome
        for request in requests {
            RouteKilometerMarkerDrawing.drawRouteDot(
                at: request.routePoint,
                contentScale: contentScale,
                in: cgContext
            )
            guard var offset = shifts[request.kilometer]?.centerOffset else { continue }
            let size = RouteKilometerMarkerDrawing.capsuleSize(
                distanceLabel: request.distanceLabel,
                timeLabel: request.timeLabel,
                contentScale: contentScale
            )
            if imageSize.width > 1, size.width > 0 {
                let centerX = request.routePoint.x + offset.x
                let left = centerX - size.width / 2
                let right = centerX + size.width / 2
                let inset = sideInset
                var flipped = offset
                if right > imageSize.width - inset + 0.5 {
                    flipped.x = -abs(offset.x)
                } else if left < inset - 0.5 {
                    flipped.x = abs(offset.x)
                }
                if flipped != offset {
                    let trial = [request.kilometer: RouteKilometerLabelShift(centerOffset: flipped)]
                    let hits = RouteKilometerLabelPlacement.auditCollisions(
                        shifts: trial,
                        markers: [request],
                        endpointPoints: endpoints,
                        routePolyline: routePolyline,
                        contentScale: contentScale,
                        pathHalfWidth: appearance.usesShareSummaryChrome
                            ? ShareSummaryTokens.routeCasing / 2
                            : 4
                    )
                    if hits.isZero { offset = flipped }
                }
            }
            if useDetailBlue {
                RouteKilometerMarkerDrawing.drawDetailCombinedMarker(
                    distanceLabel: request.distanceLabel,
                    timeLabel: request.timeLabel,
                    routePoint: request.routePoint,
                    centerOffset: offset,
                    contentScale: contentScale,
                    in: cgContext
                )
            } else {
                RouteKilometerMarkerDrawing.drawCombinedMarker(
                    distanceLabel: request.distanceLabel,
                    timeLabel: request.timeLabel,
                    routePoint: request.routePoint,
                    centerOffset: offset,
                    contentScale: contentScale,
                    in: cgContext
                )
            }
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
