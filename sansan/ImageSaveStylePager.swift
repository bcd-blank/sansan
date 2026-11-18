//
//  ImageSaveStylePager.swift
//  sansan
//
//  Settings: horizontal pages + bottom pill-spring dots (light-mode tokens).
//  Viewing page = selected. Swipe + tap dots. No autoplay.
//

#if os(iOS)

import SwiftUI

/// Light-mode pagination tokens from docs/image-save-style-pager/pagination-dots-reference.html
/// (do NOT use black-stage dark tokens).
private enum ImageSaveStylePagerTokens {
    static let fill3 = Color(red: 23 / 255, green: 24 / 255, blue: 26 / 255).opacity(0.12)
    static let inverse = Color(red: 14 / 255, green: 15 / 255, blue: 17 / 255)
    static let surface = Color.white
    static let card = Color(red: 247 / 255, green: 247 / 255, blue: 246 / 255)

    static let dotSize: CGFloat = 8
    static let pillWidth: CGFloat = 20
    static let gap: CGFloat = 14
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
        VStack(spacing: 16) {
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
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityLabel("이미지 저장 방식")

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
        }
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

/// Offscreen export / snapshot helper (illustrative page art).
struct ImageSaveStylePageExportPreview: View {
    let style: HikingRecordImageSaveStyle

    var body: some View {
        ImageSaveStylePagePreview(style: style)
    }
}

// MARK: - Page preview (illustrative; not live map render)

private struct ImageSaveStylePagePreview: View {
    let style: HikingRecordImageSaveStyle

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            previewArt
            LinearGradient(
                colors: [.clear, .black.opacity(0.35)],
                startPoint: .center,
                endPoint: .bottom
            )
            Text(style.label)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.leading, 16)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ImageSaveStylePagerTokens.surface)
    }

    @ViewBuilder
    private var previewArt: some View {
        switch style {
        case .card:
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.72, blue: 0.55),
                                Color(red: 0.42, green: 0.58, blue: 0.42),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 96)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .frame(height: 72)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(Color.black.opacity(0.12)).frame(width: 48, height: 6)
                            Capsule().fill(Color.black.opacity(0.20)).frame(width: 88, height: 10)
                            HStack(spacing: 8) {
                                Capsule().fill(Color.black.opacity(0.10)).frame(width: 40, height: 6)
                                Capsule().fill(Color.black.opacity(0.10)).frame(width: 40, height: 6)
                            }
                        }
                        .padding(12)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ImageSaveStylePagerTokens.card)

        case .summary:
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color(red: 228 / 255, green: 228 / 255, blue: 228 / 255))
                Capsule()
                    .stroke(Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255), lineWidth: 3)
                    .frame(width: 140, height: 90)
                    .rotationEffect(.degrees(-28))
                    .offset(x: 20, y: -36)
                    .opacity(0.9)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .frame(height: 78)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 6)
            }

        case .simpleColor:
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color(red: 0.62, green: 0.78, blue: 0.55),
                        Color(red: 0.45, green: 0.62, blue: 0.42),
                        Color(red: 0.72, green: 0.82, blue: 0.68),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Capsule()
                    .stroke(Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255), lineWidth: 3)
                    .frame(width: 140, height: 90)
                    .rotationEffect(.degrees(-28))
                    .offset(x: 20, y: -36)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.65), lineWidth: 1)
                    }
                    .frame(height: 78)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 8)
            }
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
