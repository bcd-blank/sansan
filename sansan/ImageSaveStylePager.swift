//
//  ImageSaveStylePager.swift
//  sansan
//
//  Settings: horizontal pages + bottom pill-spring dots (light-mode tokens).
//  Swipe/dots change VIEWED page only — selection is preference storage.
//  v14 JW: image-as-card (radius+shadow, list-aligned width, 314∶220 height);
//  option title OVERLAPS preview — dark pill top-LEADING (same Y/margin as chip);
//  「선택 완료」 top-trailing only on saved style; section footer follows VIEWED page.
//  Horizontal ScrollView paging; dots ON the card — no Form pale band under preview.
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
    /// Settings preview framing (pad 28 → 314×220). Width = list card; height = width × 220/314.
    /// At list width ≈ 370pt → card height ≈ **259pt** (Android matches this SoT).
    static let cardAspectWidth: CGFloat = 314
    static let cardAspectHeight: CGFloat = 220
    static let pageCorner: CGFloat = 24
    /// Overlaid on preview (Pagination Dots slide caption: 16 / 14).
    static let titleSize: CGFloat = 17
    /// Title top-leading mirrors chip top-trailing (same Y + inset).
    static let titleTop: CGFloat = 12
    static let titleLeading: CGFloat = 12
    static let selectedChipTop: CGFloat = 12
    static let selectedChipTrailing: CGFloat = 12
    /// Dots sit ON the card (bottom inset) — no Form gutter under the preview.
    static let dotsBottomInset: CGFloat = 10
    /// Hairline shadow only — large blur read as a pale band under the card.
    static let cardShadow = Color.black.opacity(0.08)
    static let cardShadowRadius: CGFloat = 1
    static let cardShadowY: CGFloat = 0.5
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
        ZStack {
            // Opaque plate — preview PNGs are translucent; without this, Form list
            // ghosts through the glass and reads as a pale strip under the card.
            RoundedRectangle(cornerRadius: ImageSaveStylePagerTokens.pageCorner, style: .continuous)
                .fill(Color.white)

            // ScrollView paging — no UIPageControl gutter under the image.
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

            // Dots ON the card — eliminates Form pale band under the preview.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
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
                .padding(.bottom, ImageSaveStylePagerTokens.dotsBottomInset)
            }
        }
        .aspectRatio(
            ImageSaveStylePagerTokens.cardAspectWidth / ImageSaveStylePagerTokens.cardAspectHeight,
            contentMode: .fit
        )
        .frame(maxWidth: .infinity)
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: ImageSaveStylePagerTokens.pageCorner, style: .continuous))
        .shadow(
            color: ImageSaveStylePagerTokens.cardShadow,
            radius: ImageSaveStylePagerTokens.cardShadowRadius,
            x: 0,
            y: ImageSaveStylePagerTokens.cardShadowY
        )
        .contentShape(RoundedRectangle(cornerRadius: ImageSaveStylePagerTokens.pageCorner, style: .continuous))
        .onTapGesture {
            selection = viewedPage
        }
        .accessibilityLabel("이미지 저장 방식")
        .accessibilityIdentifier("imageSaveStylePager")
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
                    // v14: top-leading dark pill — same Y/inset as Morph chip; clear of glass/4.20.
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
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
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
                .allowsHitTesting(false)
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
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(labels.indices.contains(index) ? labels[index] : "Slide \(index + 1)")
                    .accessibilityIdentifier("imageSaveStyleDot\(index)")
                    .accessibilityAddTraits(index == selectedIndex ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
        // Height = dotSize only — a taller frame padded Form grey above the dots
        // and reintroduced the pale strip under the card.
        .frame(width: trackWidth, height: ImageSaveStylePagerTokens.dotSize, alignment: .leading)
        .frame(maxWidth: .infinity)
        .onAppear { snapPill(to: selectedIndex, animated: false) }
        .onChange(of: selectedIndex) { old, new in
            movePill(from: old, to: new)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("저장 방식 미리보기 페이지")
    }

    private func leading(for index: Int) -> CGFloat {
        CGFloat(index) * (ImageSaveStylePagerTokens.dotSize + ImageSaveStylePagerTokens.gap)
            - (ImageSaveStylePagerTokens.pillWidth - ImageSaveStylePagerTokens.dotSize) / 2
    }

    private func snapPill(to index: Int, animated: Bool) {
        let targetLeading = leading(for: index)
        let targetTrailing = targetLeading + ImageSaveStylePagerTokens.pillWidth
        if animated {
            withAnimation(
                .interpolatingSpring(
                    stiffness: ImageSaveStylePagerTokens.springPage.stiffness,
                    damping: ImageSaveStylePagerTokens.springPage.damping
                )
            ) {
                pillLeading = targetLeading
                pillTrailing = targetTrailing
            }
        } else {
            pillLeading = targetLeading
            pillTrailing = targetTrailing
        }
        ready = true
    }

    private func movePill(from old: Int, to new: Int) {
        guard ready else {
            snapPill(to: new, animated: false)
            return
        }
        let targetLeading = leading(for: new)
        let targetTrailing = targetLeading + ImageSaveStylePagerTokens.pillWidth
        let movingRight = new > old
        let lead = ImageSaveStylePagerTokens.springLead
        let trail = ImageSaveStylePagerTokens.springTrail
        if movingRight {
            withAnimation(.interpolatingSpring(stiffness: lead.stiffness, damping: lead.damping)) {
                pillTrailing = targetTrailing
            }
            withAnimation(.interpolatingSpring(stiffness: trail.stiffness, damping: trail.damping)) {
                pillLeading = targetLeading
            }
        } else {
            withAnimation(.interpolatingSpring(stiffness: lead.stiffness, damping: lead.damping)) {
                pillLeading = targetLeading
            }
            withAnimation(.interpolatingSpring(stiffness: trail.stiffness, damping: trail.damping)) {
                pillTrailing = targetTrailing
            }
        }
    }
}

#endif
