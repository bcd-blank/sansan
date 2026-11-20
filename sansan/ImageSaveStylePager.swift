//
//  ImageSaveStylePager.swift
//  sansan
//
//  Settings: horizontal pages + bottom pill-spring dots (light-mode tokens).
//  Swipe/dots change VIEWED page only — selection is preference storage.
//  v21 JW: equal cards 314∶510. Fit-width then crop (native aspect, no stretch).
//  DC: title cut off; map+6 data cards; elev top slight. SG/SC same rule.
//  Flat dim (black @20%) — NO gradient, NO title capsule. Check above dim.
//  Tokens: docs/design-tokens/image-save-preview.json (Android 1:1).
//  Preview thumbs only — save/export untouched.
//

#if os(iOS)

import SwiftUI
import UIKit

/// Shared with Android ImageSaveStylePagerTokens / image-save-preview.json.
private enum ImageSaveStylePagerTokens {
    static let fill3 = Color(red: 23 / 255, green: 24 / 255, blue: 26 / 255).opacity(0.12)
    static let inverse = Color(red: 14 / 255, green: 15 / 255, blue: 17 / 255)
    static let surface = Color.white
    /// Morph Select / green chip (`--green`, `--on-green`) — 「선택 완료」 SoT.
    static let selectGreen = Color(red: 52 / 255, green: 209 / 255, blue: 122 / 255) // #34d17a
    static let onGreen = Color(red: 4 / 255, green: 20 / 255, blue: 10 / 255) // #04140a

    static let dotSize: CGFloat = 8
    static let pillWidth: CGFloat = 20
    static let gap: CGFloat = 14

    static let cardAspectWidth: CGFloat = ChromeSizes.ImageSavePreview.cardAspectWidth
    static let cardAspectHeight: CGFloat = ChromeSizes.ImageSavePreview.cardAspectHeight
    static let pageCorner: CGFloat = ChromeSizes.ImageSavePreview.pageCorner
    static let dimOpacity: CGFloat = ChromeSizes.ImageSavePreview.dimOpacity
    static let titleSize: CGFloat = ChromeSizes.ImageSavePreview.titleSize
    static let titleTop: CGFloat = ChromeSizes.ImageSavePreview.titleTop
    static let titleLeading: CGFloat = ChromeSizes.ImageSavePreview.titleLeading
    static let selectedChipTop: CGFloat = ChromeSizes.ImageSavePreview.selectedChipTop
    static let selectedChipTrailing: CGFloat = ChromeSizes.ImageSavePreview.selectedChipTrailing
    static let dotsTopGap: CGFloat = ChromeSizes.ImageSavePreview.dotsTopGap

    static let springLead = (stiffness: 520.0, damping: 34.0)
    static let springTrail = (stiffness: 140.0, damping: 18.0)
    static let springPage = (stiffness: 170.0, damping: 22.0)
}

struct ImageSaveStylePager: View {
    /// Saved preference — checkbox follows this, not the viewed page.
    @Binding var selection: HikingRecordImageSaveStyle
    /// Viewed page (swipe / dots). Drives section footer; does not write preference.
    @Binding var viewedPage: HikingRecordImageSaveStyle

    private let styles = HikingRecordImageSaveStyle.pagerOrder

    private var viewedIndex: Int {
        styles.firstIndex(of: viewedPage) ?? 0
    }

    private var showsCheckOnViewedPage: Bool {
        viewedPage == selection
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Opaque plate inside the card only — preview PNGs are translucent;
                // without this, Form list ghosts through the glass. Not an outer wrap.
                RoundedRectangle(cornerRadius: ImageSaveStylePagerTokens.pageCorner, style: .continuous)
                    .fill(Color.white)

                GeometryReader { geo in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(styles) { style in
                                pageImage(for: style, in: geo.size)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                                    .id(style)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(style.label)
                                    .accessibilityAddTraits(style == selection ? [.isSelected, .isButton] : .isButton)
                                    .accessibilityValue(style == selection ? "선택 완료" : "")
                                    .accessibilityHint("탭하면 이 저장 방식으로 선택합니다. 스와이프는 미리보기만 바꿉니다.")
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: viewedPageScrollID)
                }

                // Flat uniform dim (JW: no gradient). Under title + check.
                Color.black.opacity(ImageSaveStylePagerTokens.dimOpacity)
                    .allowsHitTesting(false)

                // Title + check above dim.
                cardOverlays
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
            .aspectRatio(
                ImageSaveStylePagerTokens.cardAspectWidth / ImageSaveStylePagerTokens.cardAspectHeight,
                contentMode: .fit
            )
            .frame(maxWidth: .infinity)
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: ImageSaveStylePagerTokens.pageCorner, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: ImageSaveStylePagerTokens.pageCorner, style: .continuous))
            .onTapGesture {
                selection = viewedPage
            }
            .accessibilityLabel("이미지 저장 방식")
            .accessibilityIdentifier("imageSaveStylePager")

            PillSpringDots(
                count: styles.count,
                selectedIndex: viewedIndex,
                onSelect: { index in
                    guard styles.indices.contains(index) else { return }
                    withAnimation(
                        .interpolatingSpring(
                            stiffness: ImageSaveStylePagerTokens.springPage.stiffness,
                            damping: ImageSaveStylePagerTokens.springPage.damping
                        )
                    ) {
                        viewedPage = styles[index]
                    }
                },
                labels: styles.map(\.label)
            )
            .padding(.top, ImageSaveStylePagerTokens.dotsTopGap)
        }
#if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .uiTestSaveStylePage)) { note in
            guard let raw = note.userInfo?["index"] as? Int,
                  styles.indices.contains(raw) else { return }
            withAnimation(
                .interpolatingSpring(
                    stiffness: ImageSaveStylePagerTokens.springPage.stiffness,
                    damping: ImageSaveStylePagerTokens.springPage.damping
                )
            ) {
                viewedPage = styles[raw]
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .uiTestSaveStyleSelect)) { note in
            guard let raw = note.userInfo?["index"] as? Int,
                  styles.indices.contains(raw) else { return }
            selection = styles[raw]
        }
#endif
    }

    private var viewedPageScrollID: Binding<HikingRecordImageSaveStyle?> {
        Binding(
            get: { viewedPage },
            set: { newValue in
                guard let newValue else { return }
                withAnimation(
                    .interpolatingSpring(
                        stiffness: ImageSaveStylePagerTokens.springPage.stiffness,
                        damping: ImageSaveStylePagerTokens.springPage.damping
                    )
                ) {
                    viewedPage = newValue
                }
            }
        )
    }

    private var cardOverlays: some View {
        VStack {
            HStack(alignment: .top) {
                // White text only — no dark capsule (v21 JW).
                Text(viewedPage.label)
                    .font(.system(size: ImageSaveStylePagerTokens.titleSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                    .accessibilityIdentifier("imageSaveStyleTitle")
                    .padding(.leading, ImageSaveStylePagerTokens.titleLeading)
                    .padding(.top, ImageSaveStylePagerTokens.titleTop)
                Spacer(minLength: 0)
                if showsCheckOnViewedPage {
                    selectedCompleteChip
                        .padding(.top, ImageSaveStylePagerTokens.selectedChipTop)
                        .padding(.trailing, ImageSaveStylePagerTokens.selectedChipTrailing)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var selectedCompleteChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
            Text("선택 완료")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(ImageSaveStylePagerTokens.onGreen)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(ImageSaveStylePagerTokens.selectGreen)
        )
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .accessibilityIdentifier("imageSaveStyleSelectedBadge")
    }

    /// Fit width (native aspect) then crop height into the equal card. No stretch.
    @ViewBuilder
    private func pageImage(for style: HikingRecordImageSaveStyle, in size: CGSize) -> some View {
        if let image = ImageSaveStylePreviewImages.image(for: style) {
            let fittedHeight = size.width * (image.size.height / max(image.size.width, 1))
            let cropTopPx = ImageSaveStylePreviewImages.cropTopPx(for: style)
            // Thumbs are pre-cropped @1206×1959 (= card aspect). Runtime still uses
            // width-fit + top-aligned clip so Android can mirror the same rule on
            // full native saves using cropTopPxAt1206 tokens.
            let scale = size.width / max(image.size.width, 1)
            let cropTop = cropTopPx * scale
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

    /// Crop top in source px when bitmap width == referenceBitmapWidth (1206).
    /// Pre-baked thumbs already apply this crop → return 0 at runtime for those.
    /// Android applying the rule to full native saves must use ChromeSizes values.
    static func cropTopPx(for style: HikingRecordImageSaveStyle) -> CGFloat {
        // Bundle thumbs are already cropped to 314∶510; no further runtime offset.
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

// MARK: - Pill spring dots

private struct PillSpringDots: View {
    let count: Int
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let labels: [String]

    @State private var pillLeading: CGFloat = 0
    @State private var pillTrailing: CGFloat = ImageSaveStylePagerTokens.pillWidth
    @State private var ready = false

    private var trackWidth: CGFloat {
        let n = CGFloat(max(count, 1))
        return n * ImageSaveStylePagerTokens.dotSize
            + max(n - 1, 0) * ImageSaveStylePagerTokens.gap
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(ImageSaveStylePagerTokens.inverse)
                .frame(
                    width: max(ImageSaveStylePagerTokens.dotSize, pillTrailing - pillLeading),
                    height: ImageSaveStylePagerTokens.dotSize
                )
                .offset(x: pillLeading)
                .accessibilityHidden(true)

            HStack(spacing: ImageSaveStylePagerTokens.gap) {
                ForEach(0..<count, id: \.self) { index in
                    Button {
                        onSelect(index)
                    } label: {
                        Circle()
                            .fill(ImageSaveStylePagerTokens.fill3)
                            .frame(
                                width: ImageSaveStylePagerTokens.dotSize,
                                height: ImageSaveStylePagerTokens.dotSize
                            )
                            .opacity(index == selectedIndex ? 0 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(labels.indices.contains(index) ? labels[index] : "page \(index + 1)")
                    .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
                    .accessibilityIdentifier("imageSaveStyleDot\(index)")
                }
            }
        }
        .frame(width: trackWidth, height: ImageSaveStylePagerTokens.dotSize, alignment: .leading)
        .frame(maxWidth: .infinity)
        .onAppear {
            snap(to: selectedIndex, animated: false)
            ready = true
        }
        .onChange(of: selectedIndex) { _, newValue in
            guard ready else { return }
            snap(to: newValue, animated: true)
        }
    }

    private func targetLeading(for index: Int) -> CGFloat {
        CGFloat(index) * (ImageSaveStylePagerTokens.dotSize + ImageSaveStylePagerTokens.gap)
            - (ImageSaveStylePagerTokens.pillWidth - ImageSaveStylePagerTokens.dotSize) / 2
    }

    private func snap(to index: Int, animated: Bool) {
        let targetLeading = targetLeading(for: index)
        let targetTrailing = targetLeading + ImageSaveStylePagerTokens.pillWidth
        if !animated {
            withAnimation(
                .interpolatingSpring(
                    stiffness: ImageSaveStylePagerTokens.springPage.stiffness,
                    damping: ImageSaveStylePagerTokens.springPage.damping
                )
            ) {
                pillLeading = targetLeading
                pillTrailing = targetTrailing
            }
            return
        }
        let lead = ImageSaveStylePagerTokens.springLead
        let trail = ImageSaveStylePagerTokens.springTrail
        withAnimation(.interpolatingSpring(stiffness: lead.stiffness, damping: lead.damping)) {
            pillLeading = targetLeading
        }
        withAnimation(.interpolatingSpring(stiffness: trail.stiffness, damping: trail.damping)) {
            pillTrailing = targetTrailing
        }
    }
}

#endif
