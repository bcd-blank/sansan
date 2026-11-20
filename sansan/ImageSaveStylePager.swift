//
//  ImageSaveStylePager.swift
//  sansan
//
//  Settings: horizontal GALLERY of small thumbs (v22 JW).
//  ~42% content width → two fully visible + third peeking. Gap 12. Leading 16.
//  Tap selects. Selected: green check circle + subtle border (no full Morph chip).
//  No page dots. Description stays in section footer (viewed/selected).
//  v21 crop/dim rules kept: fit-width then crop, flat dim 0.2, white title no capsule.
//  Tokens: docs/design-tokens/image-save-preview.json (Android 1:1).
//  Preview thumbs only — save/export untouched.
//

#if os(iOS)

import SwiftUI
import UIKit

private enum ImageSaveStylePagerTokens {
    static let surface = Color.white
    static let selectGreen = Color(red: 52 / 255, green: 209 / 255, blue: 122 / 255) // #34d17a
    static let onGreen = Color(red: 4 / 255, green: 20 / 255, blue: 10 / 255) // #04140a

    static let cardAspectWidth: CGFloat = ChromeSizes.ImageSavePreview.cardAspectWidth
    static let cardAspectHeight: CGFloat = ChromeSizes.ImageSavePreview.cardAspectHeight
    static let pageCorner: CGFloat = ChromeSizes.ImageSavePreview.pageCorner
    static let dimOpacity: CGFloat = ChromeSizes.ImageSavePreview.dimOpacity
    static let titleSize: CGFloat = ChromeSizes.ImageSavePreview.titleSize
    static let titleTop: CGFloat = ChromeSizes.ImageSavePreview.titleTop
    static let titleLeading: CGFloat = ChromeSizes.ImageSavePreview.titleLeading
    static let selectedBadgeTop: CGFloat = ChromeSizes.ImageSavePreview.selectedBadgeTop
    static let selectedBadgeTrailing: CGFloat = ChromeSizes.ImageSavePreview.selectedBadgeTrailing
    static let selectedBadgeDiameter: CGFloat = ChromeSizes.ImageSavePreview.selectedBadgeDiameter
    static let selectedBadgeCheckSize: CGFloat = ChromeSizes.ImageSavePreview.selectedBadgeCheckSize
    static let selectedBorderWidth: CGFloat = ChromeSizes.ImageSavePreview.selectedBorderWidth
    static let cardWidthFraction: CGFloat = ChromeSizes.ImageSavePreview.cardWidthFraction
    static let gap: CGFloat = ChromeSizes.ImageSavePreview.gap
    static let leadingInset: CGFloat = ChromeSizes.ImageSavePreview.leadingInset
    static let trailingInset: CGFloat = ChromeSizes.ImageSavePreview.trailingInset
}

struct ImageSaveStylePager: View {
    /// Saved preference — check badge follows this.
    @Binding var selection: HikingRecordImageSaveStyle
    /// Drives section footer; follows scroll focus + tap.
    @Binding var viewedPage: HikingRecordImageSaveStyle

    private let styles = HikingRecordImageSaveStyle.pagerOrder
    /// List row height — derived from content width × card fraction × aspect.
    @State private var galleryHeight: CGFloat = 220

    var body: some View {
        GeometryReader { geo in
            let contentWidth = max(geo.size.width, 1)
            let cardWidth = contentWidth * ImageSaveStylePagerTokens.cardWidthFraction
            let cardHeight = cardWidth
                * (ImageSaveStylePagerTokens.cardAspectHeight / ImageSaveStylePagerTokens.cardAspectWidth)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: ImageSaveStylePagerTokens.gap) {
                    ForEach(styles) { style in
                        galleryCard(for: style, size: CGSize(width: cardWidth, height: cardHeight))
                            .frame(width: cardWidth, height: cardHeight)
                            .id(style)
                    }
                }
                .scrollTargetLayout()
                .padding(.leading, ImageSaveStylePagerTokens.leadingInset)
                .padding(.trailing, ImageSaveStylePagerTokens.trailingInset)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: viewedPageScrollID)
            .frame(width: contentWidth, height: cardHeight, alignment: .top)
            .onAppear { galleryHeight = cardHeight }
            .onChange(of: contentWidth) { _, newWidth in
                let w = newWidth * ImageSaveStylePagerTokens.cardWidthFraction
                galleryHeight = w
                    * (ImageSaveStylePagerTokens.cardAspectHeight / ImageSaveStylePagerTokens.cardAspectWidth)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: galleryHeight)
        .accessibilityLabel("이미지 저장 방식")
        .accessibilityIdentifier("imageSaveStylePager")
#if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .uiTestSaveStylePage)) { note in
            guard let raw = note.userInfo?["index"] as? Int,
                  styles.indices.contains(raw) else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                viewedPage = styles[raw]
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .uiTestSaveStyleSelect)) { note in
            guard let raw = note.userInfo?["index"] as? Int,
                  styles.indices.contains(raw) else { return }
            selection = styles[raw]
            viewedPage = styles[raw]
        }
#endif
    }

    private var viewedPageScrollID: Binding<HikingRecordImageSaveStyle?> {
        Binding(
            get: { viewedPage },
            set: { newValue in
                guard let newValue else { return }
                viewedPage = newValue
            }
        )
    }

    private func galleryCard(for style: HikingRecordImageSaveStyle, size: CGSize) -> some View {
        let isSelected = style == selection
        return ZStack {
            RoundedRectangle(cornerRadius: ImageSaveStylePagerTokens.pageCorner, style: .continuous)
                .fill(ImageSaveStylePagerTokens.surface)

            pageImage(for: style, in: size)
                .frame(width: size.width, height: size.height)
                .clipped()

            Color.black.opacity(ImageSaveStylePagerTokens.dimOpacity)
                .allowsHitTesting(false)

            VStack {
                HStack(alignment: .top) {
                    Text(style.label)
                        .font(.system(size: ImageSaveStylePagerTokens.titleSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.leading, ImageSaveStylePagerTokens.titleLeading)
                        .padding(.top, ImageSaveStylePagerTokens.titleTop)
                    Spacer(minLength: 4)
                    if isSelected {
                        selectedCheckBadge
                            .padding(.top, ImageSaveStylePagerTokens.selectedBadgeTop)
                            .padding(.trailing, ImageSaveStylePagerTokens.selectedBadgeTrailing)
                    }
                }
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: ImageSaveStylePagerTokens.pageCorner, style: .continuous)
                .strokeBorder(
                    isSelected ? ImageSaveStylePagerTokens.selectGreen : Color.clear,
                    lineWidth: ImageSaveStylePagerTokens.selectedBorderWidth
                )
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: ImageSaveStylePagerTokens.pageCorner, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: ImageSaveStylePagerTokens.pageCorner, style: .continuous))
        .onTapGesture {
            selection = style
            viewedPage = style
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityValue(isSelected ? "선택 완료" : "")
        .accessibilityHint("탭하면 이 저장 방식으로 선택합니다.")
        .accessibilityIdentifier("imageSaveStyleThumb_\(style.rawValue)")
    }

    private var selectedCheckBadge: some View {
        // Compact check circle — full 「선택 완료」 chip is too wide on ~42% thumbs.
        ZStack {
            Circle()
                .fill(ImageSaveStylePagerTokens.selectGreen)
            Image(systemName: "checkmark")
                .font(.system(size: ImageSaveStylePagerTokens.selectedBadgeCheckSize, weight: .bold))
                .foregroundStyle(ImageSaveStylePagerTokens.onGreen)
        }
        .frame(
            width: ImageSaveStylePagerTokens.selectedBadgeDiameter,
            height: ImageSaveStylePagerTokens.selectedBadgeDiameter
        )
        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
        .accessibilityIdentifier("imageSaveStyleSelectedBadge")
    }

    /// Fit width (native aspect) then crop height. Thumbs are pre-cropped @314∶510.
    @ViewBuilder
    private func pageImage(for style: HikingRecordImageSaveStyle, in size: CGSize) -> some View {
        if let image = ImageSaveStylePreviewImages.image(for: style) {
            let fittedHeight = size.width * (image.size.height / max(image.size.width, 1))
            let cropTop = ImageSaveStylePreviewImages.cropTopPx(for: style)
                * (size.width / max(image.size.width, 1))
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: fittedHeight)
                .offset(y: -cropTop)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipped()
        } else {
            ImageSaveStylePagerTokens.surface
        }
    }
}

/// Offscreen export / snapshot helper (real sample thumb).
struct ImageSaveStylePageExportPreview: View {
    let style: HikingRecordImageSaveStyle

    var body: some View {
        Group {
            if let image = ImageSaveStylePreviewImages.image(for: style) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white
            }
        }
        .clipped()
    }
}

enum ImageSaveStylePreviewImages {
    static func image(for style: HikingRecordImageSaveStyle) -> UIImage? {
        let name: String
        switch style {
        case .card: name = "data-card"
        case .summary: name = "simple-grey"
        case .simpleColor: name = "simple-color"
        }
        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "image-save-style-previews"),
            Bundle.main.url(forResource: name, withExtension: "png"),
        ]
        for url in candidates {
            if let url, let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }
        return UIImage(named: "ImageSavePreview-\(name)")
    }

    /// Bundle thumbs already cropped → 0 at runtime.
    static func cropTopPx(for style: HikingRecordImageSaveStyle) -> CGFloat {
        _ = style
        return 0
    }

    static func documentedCropTopPx(for style: HikingRecordImageSaveStyle) -> CGFloat {
        switch style {
        case .card: ChromeSizes.ImageSavePreview.CropTopPxAt1206.dataCard
        case .summary: ChromeSizes.ImageSavePreview.CropTopPxAt1206.simpleGrey
        case .simpleColor: ChromeSizes.ImageSavePreview.CropTopPxAt1206.simpleColor
        }
    }
}

#endif
