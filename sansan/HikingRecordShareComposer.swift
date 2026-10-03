//
//  HikingRecordShareComposer.swift
//  sansan
//
//  기록 상세와 동일한 SwiftUI 레이아웃으로 공유·저장 이미지 생성.
//

#if os(iOS)

import SwiftUI
import UIKit

/// 공유·저장 PNG 형식.
enum HikingRecordShareExportFormat {
    /// 콘텐츠 높이에 맞춤 — 1080pt 너비.
    case contentSized
    /// 기기 화면 너비 × 콘텐츠 전체 높이 (사진 저장).
    case fullScreen
    /// 1080×1920(9:16) 안에 전체를 축소해 맞춤 — SNS 스토리용.
    case nineBySixteen
}

@MainActor
enum HikingRecordShareDeviceMetrics {
    private static let inlineNavigationBarHeight: CGFloat = 44

    private static var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }

    static var foregroundWindow: UIWindow? {
        guard let scene = activeWindowScene else { return nil }
        return scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
    }

    static var fullScreenBounds: CGSize {
        if let scene = activeWindowScene {
            return scene.screen.bounds.size
        }
        if let window = foregroundWindow {
            return window.bounds.size
        }
        return CGSize(width: 393, height: 852)
    }

    static var detailViewportHeight: CGFloat {
        fullScreenBounds.height - detailViewportTopInset
    }

    static var detailViewportTopInset: CGFloat {
        guard let window = foregroundWindow else {
            return inlineNavigationBarHeight
        }
        return window.safeAreaInsets.top + inlineNavigationBarHeight
    }

    static var nativeScale: CGFloat {
        if let scene = activeWindowScene {
            return scene.screen.nativeScale
        }
        if let window = foregroundWindow {
            return window.screen.nativeScale
        }
        return 3
    }

    static var detailContentWidth: CGFloat {
        max(fullScreenBounds.width - HikingRecordCardLayout.detailContentWidthInset, 0)
    }

    static var detailMapCanvasSize: CGSize {
        CGSize(
            width: detailContentWidth,
            height: HikingRecordCardLayout.detailMapHeight(
                contentWidth: detailContentWidth,
                viewportHeight: detailViewportHeight
            )
        )
    }

    static var detailMapExportCanvasSize: CGSize {
        RouteMapOverlayMetrics.mapExportCanvasSize(fromFullMapSize: detailMapCanvasSize)
    }
}

/// 기록 상세와 동일한 구성·비율의 공유·저장 카드.
struct HikingRecordShareCardView: View {
    let record: SavedHikingSession
    let routeImage: UIImage
    var format: HikingRecordShareExportFormat = .contentSized

    static let legacyExportWidth: CGFloat = 1080
    static let nineBySixteenHeight: CGFloat = 1920

    fileprivate var exportWidth: CGFloat {
        switch format {
        case .fullScreen:
            HikingRecordShareDeviceMetrics.fullScreenBounds.width
        case .contentSized, .nineBySixteen:
            Self.legacyExportWidth
        }
    }

    private var screenScale: CGFloat {
        exportWidth / HikingRecordCardLayout.referenceScreenWidth
    }

    private var horizontalPadding: CGFloat {
        HikingRecordCardLayout.detailHorizontalPadding.recordScaled(screenScale)
    }

    fileprivate var contentWidth: CGFloat {
        exportWidth - HikingRecordCardLayout.detailContentWidthInset.recordScaled(screenScale)
    }

    private var layoutScale: CGFloat { contentWidth / HikingRecordCardLayout.referenceContentWidth }

    private var mapCornerRadius: CGFloat {
        HikingRecordCardLayout.mapCornerRadius.recordScaled(layoutScale)
    }

    /// 경로 PNG 실제 종횡비 그대로 — 저장 설정대로 캡처된 경로를 크롭/왜곡 없이 1:1 표시.
    private var routeImageAspect: CGFloat {
        routeImage.size.height / max(routeImage.size.width, 1)
    }

    /// 지도 프레임 높이 = 콘텐츠 너비 × 경로 PNG 종횡비. `scaledToFit`과 함께 크롭 없음.
    fileprivate var mapHeight: CGFloat {
        contentWidth * routeImageAspect
    }

    private var brandTitleFontSize: CGFloat {
        contentWidth * HikingRecordCardLayout.exportBrandTitleFontRatio
    }

    private var brandTitleTopPadding: CGFloat {
        HikingRecordCardLayout.exportBrandTitleTopPadding.recordScaled(screenScale)
    }

    private var brandTitleBlockHeight: CGFloat {
        brandTitleTopPadding + brandTitleFontSize
    }

    private var showsBrandLogo: Bool {
        HikingSnapshotPreferences.style.showsBrandLogo
    }

    private var showsLegalAttribution: Bool {
        format != .fullScreen
    }

    private var brandLogoSizeScale: CGFloat {
        format == .fullScreen ? 0.6 : 1
    }

    /// 레이아웃 상수 합산 — 걸음수·칼로리·고도/심박 카드 포함.
    fileprivate var exportContentHeight: CGFloat {
        let bottomPad = HikingRecordCardLayout.detailBottomPadding.recordScaled(screenScale)
        let gap = HikingRecordCardLayout.detailSectionSpacing.recordScaled(screenScale)
        let titleHeader = HikingRecordCardLayout.estimatedTitleHeaderHeight(
            scale: layoutScale,
            showsDateSubtitle: !(record.memo?.isEmpty ?? true),
            compact: true,
            showsProfileAvatar: true
        )
        let weatherCard: CGFloat = record.weather == nil
            ? 0
            : gap + HikingRecordCardLayout.estimatedWeatherCardHeight(scale: layoutScale)
        let summary = HikingRecordCardLayout.estimatedSummaryHeight(scale: layoutScale)
        let buffer = HikingRecordCardLayout.exportContentHeightBuffer.recordScaled(screenScale)
        return brandTitleBlockHeight
            + titleHeader
            + weatherCard
            + gap
            + mapHeight
            + gap
            + summary
            + bottomPad
            + buffer
    }

    fileprivate var exportPixelScale: CGFloat {
        format == .fullScreen ? HikingRecordShareDeviceMetrics.nativeScale : 2
    }

    var body: some View {
        exportRoot
    }

    /// 높이 제한 없음 — 캡처 시 바깥에서 bounds만 지정.
    fileprivate var exportRoot: some View {
        cardContent
            .frame(width: exportWidth, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .ignoresSafeArea()
    }

    private var cardContent: some View {
        VStack(spacing: HikingRecordCardLayout.detailSectionSpacing.recordScaled(screenScale)) {
            VStack(alignment: .leading, spacing: 0) {
                shareBrandTitle
                HikingRecordTitleCard(record: record, layoutScale: layoutScale, compact: true, showsProfileAvatar: true)
                    .frame(width: contentWidth, alignment: .leading)
            }

            if let weather = record.weather {
                HikingRecordWeatherCard(weather: weather, layoutScale: layoutScale)
                    .frame(width: contentWidth, alignment: .leading)
            }

            shareMapSection

            HikingRecordSummarySection(record: record)
                .environment(\.recordCardLayoutScale, layoutScale)
                .frame(width: contentWidth, alignment: .topLeading)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, HikingRecordCardLayout.detailBottomPadding.recordScaled(screenScale))
    }

    private var shareBrandTitle: some View {
        Text("sansan")
            .font(.system(size: brandTitleFontSize, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, brandTitleTopPadding)
            .accessibilityAddTraits(.isHeader)
    }

    private var shareMapSection: some View {
        RouteMapImageCardChrome(
            showsBrandLogo: showsBrandLogo,
            showsLegalAttribution: showsLegalAttribution,
            brandLogoSizeScale: brandLogoSizeScale
        ) {
            Image(uiImage: routeImage)
                .resizable()
                .scaledToFit()
                .frame(width: contentWidth, height: mapHeight)
        }
        .frame(width: contentWidth, height: mapHeight)
        .clipShape(RoundedRectangle(cornerRadius: mapCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: mapCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

@MainActor
enum HikingRecordShareComposer {
    static func render(
        record: SavedHikingSession,
        routeImage: UIImage,
        format: HikingRecordShareExportFormat = .contentSized
    ) -> UIImage? {
        let card = HikingRecordShareCardView(
            record: record,
            routeImage: routeImage,
            format: format
        )

        guard let image = renderCardBitmap(card) else {
            return nil
        }

        switch format {
        case .contentSized, .fullScreen:
            return image
        case .nineBySixteen:
            return fitInsideNineBySixteen(image) ?? image
        }
    }

    private static func renderCardBitmap(_ card: HikingRecordShareCardView) -> UIImage? {
        let width = card.exportWidth
        let calculatedHeight = card.exportContentHeight
        let pixelScale = card.exportPixelScale

        if let window = HikingRecordShareDeviceMetrics.foregroundWindow {
            if let image = renderWithHostingController(
                card: card,
                width: width,
                height: calculatedHeight,
                pixelScale: pixelScale,
                in: window
            ) {
                return image
            }
        }

        return renderWithImageRenderer(
            card: card,
            width: width,
            height: calculatedHeight,
            pixelScale: pixelScale
        )
    }

    private static func renderWithHostingController(
        card: HikingRecordShareCardView,
        width: CGFloat,
        height: CGFloat,
        pixelScale: CGFloat,
        in window: UIWindow
    ) -> UIImage? {
        let hosting = ShareExportHostingController(rootView: card.exportRoot)
        hosting.additionalSafeAreaInsets = UIEdgeInsets(
            top: -window.safeAreaInsets.top,
            left: -window.safeAreaInsets.left,
            bottom: -window.safeAreaInsets.bottom,
            right: -window.safeAreaInsets.right
        )
        AppExportAppearance.apply(to: hosting, in: window)
        hosting.view.backgroundColor = .systemGroupedBackground
        hosting.view.isUserInteractionEnabled = false
        hosting.view.insetsLayoutMarginsFromSafeArea = false

        let container = ShareExportSafeAreaIgnoringView()
        let offscreen = CGPoint(x: -(width + 64), y: -(height + 64))
        container.frame = CGRect(origin: offscreen, size: CGSize(width: width, height: 1))
        hosting.view.frame = container.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(hosting.view)
        window.addSubview(container)
        window.layoutIfNeeded()

        let fitted = hosting.sizeThatFits(
            in: CGSize(width: width, height: UIView.layoutFittingExpandedSize.height)
        )
        let renderHeight = max(height, ceil(fitted.height) - window.safeAreaInsets.top)
        container.frame = CGRect(origin: offscreen, size: CGSize(width: width, height: renderHeight))
        window.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = pixelScale
        format.opaque = true
        let renderSize = CGSize(width: width, height: renderHeight)
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        let image = renderer.image { _ in
            hosting.view.drawHierarchy(
                in: CGRect(origin: .zero, size: renderSize),
                afterScreenUpdates: true
            )
        }
        container.removeFromSuperview()
        return image
    }

    private static func renderWithImageRenderer(
        card: HikingRecordShareCardView,
        width: CGFloat,
        height: CGFloat,
        pixelScale: CGFloat
    ) -> UIImage? {
        let window = HikingRecordShareDeviceMetrics.foregroundWindow
        let snapshot = card.exportRoot
            .preferredColorScheme(AppExportAppearance.resolvedColorScheme(in: window))
            .frame(width: width, height: height, alignment: .top)
            .background(Color(.systemGroupedBackground))

        let renderer = ImageRenderer(content: snapshot)
        renderer.scale = pixelScale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    private static func fitInsideNineBySixteen(_ contentImage: UIImage) -> UIImage? {
        let canvasSize = CGSize(
            width: HikingRecordShareCardView.legacyExportWidth,
            height: HikingRecordShareCardView.nineBySixteenHeight
        )
        let contentSize = CGSize(
            width: contentImage.size.width / contentImage.scale,
            height: contentImage.size.height / contentImage.scale
        )
        guard contentSize.width > 0, contentSize.height > 0 else { return contentImage }

        let fitScale = min(
            canvasSize.width / contentSize.width,
            canvasSize.height / contentSize.height,
            1
        )
        let drawSize = CGSize(
            width: contentSize.width * fitScale,
            height: contentSize.height * fitScale
        )
        let origin = CGPoint(
            x: (canvasSize.width - drawSize.width) / 2,
            y: (canvasSize.height - drawSize.height) / 2
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { _ in
            contentImage.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}

/// 키 윈도우에 붙여 캡처할 때 상태바 안전 영역이 이미지 상단에 들어가지 않게 합니다.
private final class ShareExportHostingController<Content: View>: UIHostingController<Content> {
    override init(rootView: Content) {
        super.init(rootView: rootView)
        safeAreaRegions = []
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ShareExportSafeAreaIgnoringView: UIView {
    override var safeAreaInsets: UIEdgeInsets { .zero }
}

#endif
