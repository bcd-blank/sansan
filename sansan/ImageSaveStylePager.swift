//
//  ImageSaveStylePager.swift
//  sansan
//
//  Settings: horizontal pages + bottom pill-spring dots (light-mode tokens).
//  Swipe/dots change VIEWED page only — selection is preference storage.
//  v18 JW: shared crop SoT 314∶370. SC/SG bias +302 + logo omit_fill in
//  preview thumbs (logo neither edge-clipped nor under name pill; title
//  clear under pill). DC bias +258 clears endpoint halo; primary rows full.
//  Page-dot gap SoT: dotsTopGap 22pt. Morph one-line chrome unchanged.
//  NO card shadow/bg. Dots BELOW preview. Title TL + Morph TR; thumbs
//  pre-framed per crop table (Android copies same numbers). 「선택 완료」
//  saved-only; footer follows VIEWED. Preview thumbs only — save untouched.
//

#if os(iOS)

import SwiftUI
import UIKit

/// Light-mode pagination tokens from docs/image-save-style-pager/pagination-dots-reference.html
/// (do NOT use black-stage dark tokens). Shared sizes with Android ImageSaveStylePagerTokens.
private enum ImageSaveStylePagerTokens {
    static let fill3 = Color(red: 23 / 255, green: 24 / 255, blue: 26 / 255).opacity(0.12)
    static let inverse = Color(red: 14 / 255, green: 15 / 255, blue: 17 / 255)
    static let surface = Color.white
    /// Morph Select / green chip (`--green`, `--on-green`) — 「선택 완료」 SoT.
    static let selectGreen = Color(red: 52 / 255, green: 209 / 255, blue: 122 / 255) // #34d17a
    static let onGreen = Color(red: 4 / 255, green: 20 / 255, blue: 10 / 255) // #04140a
    static let titlePill = Color.black.opacity(0.56)

    static let dotSize: CGFloat = 8
    static let pillWidth: CGFloat = 20
    static let gap: CGFloat = 14
    /// Settings preview framing — shared crop SoT with Android (v18).
    /// Aspect **314∶370**; at list width ≈ 370pt → card height ≈ **436pt**.
    static let cardAspectWidth: CGFloat = 314
    static let cardAspectHeight: CGFloat = 370
    static let pageCorner: CGFloat = 24
    /// Overlaid on preview (Pagination Dots slide caption: 16 / 14).
    static let titleSize: CGFloat = 17
    /// Title top-leading mirrors chip top-trailing (same Y + inset).
    static let titleTop: CGFloat = 12
    static let titleLeading: CGFloat = 12
    static let selectedChipTop: CGFloat = 12
    static let selectedChipTrailing: CGFloat = 12
    /// Dots below card — iPhone page-dot gap SoT (v18). Android must match 22pt.
    static let dotsTopGap: CGFloat = 22
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
                                pageImage(for: style)
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
            // v15: no card shadow — pale strip was the shadow/bg layer.
            .contentShape(RoundedRectangle(cornerRadius: ImageSaveStylePagerTokens.pageCorner, style: .continuous))
            .onTapGesture {
                selection = viewedPage
            }
            .accessibilityLabel("이미지 저장 방식")
            .accessibilityIdentifier("imageSaveStylePager")

            // Dots BELOW preview (v13) — not on-card.
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
            // Capture helper: change VIEWED page only (does not write preference).
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
            // Capture helper: write SAVED selection (drives 「선택 완료」 chip).
            guard let raw = note.userInfo?["index"] as? Int,
                  styles.indices.contains(raw) else { return }
            selection = styles[raw]
        }
#endif
    }

    /// ScrollPosition id binding — optional so programmatic page jumps stay in sync.
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
        ZStack {
            // Light top scrim only — title is top-leading; avoid heavy bottom wash.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.30), location: 0),
                    .init(color: .clear, location: 0.28),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                HStack(alignment: .top) {
                    // Top-leading dark pill — same Y/inset as Morph chip.
                    Text(viewedPage.label)
                        .font(.system(size: ImageSaveStylePagerTokens.titleSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(ImageSaveStylePagerTokens.titlePill)
                        )
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

    @ViewBuilder
    private func pageImage(for style: HikingRecordImageSaveStyle) -> some View {
        if let image = ImageSaveStylePreviewImages.image(for: style) {
            // Resources are pre-framed 314∶370 per shared crop SoT (see v18 CROP_SOT).
            // Fit (not Fill) so matching-aspect thumbs are not re-cropped at runtime.
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        // Xcode may flatten Resources/image-save-style-previews/*.png to the bundle root.
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
        // Lead / trail springs (reference HTML).
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
