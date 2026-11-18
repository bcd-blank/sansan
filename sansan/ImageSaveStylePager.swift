//
//  ImageSaveStylePager.swift
//  sansan
//
//  Settings: horizontal pages + bottom pill-spring dots (light-mode tokens).
//  Viewing page = selected. Swipe + tap dots. No autoplay.
//  Preview art = real sample renders (same assets as Android), not abstract shapes.
//  Simple Grey sample must show warm paper #E6E2E0 / road #EEEBE9.
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

    static let dotSize: CGFloat = 8
    static let pillWidth: CGFloat = 20
    static let gap: CGFloat = 14
    static let pageHeight: CGFloat = 220
    static let pageCorner: CGFloat = 24
    /// Option name below preview (not overlaid — v2 reject / JW v6). Shared with Android.
    static let titleSize: CGFloat = 17
    static let titleToPreviewGap: CGFloat = 12
    static let titleToDotsGap: CGFloat = 12
    static let springLead = (stiffness: 520.0, damping: 34.0)
    static let springTrail = (stiffness: 140.0, damping: 18.0)
    static let springPage = (stiffness: 170.0, damping: 22.0)
}

struct ImageSaveStylePager: View {
    @Binding var selection: HikingRecordImageSaveStyle

    private let styles = HikingRecordImageSaveStyle.pagerOrder

    private var selectedIndex: Int {
        styles.firstIndex(of: selection) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: binding) {
                ForEach(Array(styles.enumerated()), id: \.element.id) { _, style in
                    ImageSaveStylePagePreview(style: style)
                        .tag(style)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(style.label)
                        .accessibilityAddTraits(style == selection ? [.isSelected, .isButton] : .isButton)
                        .accessibilityValue(style == selection ? "선택됨" : "")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: ImageSaveStylePagerTokens.pageHeight)
            .clipShape(RoundedRectangle(cornerRadius: ImageSaveStylePagerTokens.pageCorner, style: .continuous))
            .accessibilityLabel("이미지 저장 방식")
            .accessibilityIdentifier("imageSaveStylePager")

            // Separate line under preview — never over distance numerals on the sample art.
            Text(selection.label)
                .font(.system(size: ImageSaveStylePagerTokens.titleSize, weight: .semibold))
                .foregroundStyle(ImageSaveStylePagerTokens.inverse)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, ImageSaveStylePagerTokens.titleToPreviewGap)
                .accessibilityIdentifier("imageSaveStyleTitle")

            PillSpringDots(
                count: styles.count,
                selectedIndex: selectedIndex,
                onSelect: { index in
                    guard styles.indices.contains(index) else { return }
                    withAnimation(
                        .interpolatingSpring(
                            stiffness: ImageSaveStylePagerTokens.springPage.stiffness,
                            damping: ImageSaveStylePagerTokens.springPage.damping
                        )
                    ) {
                        selection = styles[index]
                    }
                },
                labels: styles.map(\.label)
            )
            .padding(.top, ImageSaveStylePagerTokens.titleToDotsGap)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
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
                selection = styles[raw]
            }
        }
#endif
    }

    private var binding: Binding<HikingRecordImageSaveStyle> {
        Binding(
            get: { selection },
            set: { newValue in
                withAnimation(
                    .interpolatingSpring(
                        stiffness: ImageSaveStylePagerTokens.springPage.stiffness,
                        damping: ImageSaveStylePagerTokens.springPage.damping
                    )
                ) {
                    selection = newValue
                }
            }
        )
    }
}

/// Offscreen export / snapshot helper (real sample thumb).
struct ImageSaveStylePageExportPreview: View {
    let style: HikingRecordImageSaveStyle

    var body: some View {
        ImageSaveStylePagePreview(style: style)
    }
}

// MARK: - Page preview (real sample render, cropped)

private struct ImageSaveStylePagePreview: View {
    let style: HikingRecordImageSaveStyle

    var body: some View {
        ZStack {
            if let image = ImageSaveStylePreviewImages.image(for: style) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                ImageSaveStylePagerTokens.surface
            }
            // Soft bottom scrim only (Android parity) — no style-name Text on the art.
            LinearGradient(
                colors: [.clear, .black.opacity(0.22)],
                startPoint: UnitPoint(x: 0.5, y: 0.55),
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ImageSaveStylePagerTokens.surface)
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
        .frame(width: trackWidth, height: 20, alignment: .leading)
        .frame(maxWidth: .infinity)
        .onAppear { snapPill(to: selectedIndex, animated: false) }
        .onChange(of: selectedIndex) { old, new in
            movePill(from: old, to: new)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("저장 방식 페이지")
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
