//
//  HikingRecordSummaryViews.swift
//  sansan
//
//  기록 상세·공유 이미지 공통 요약 카드 UI.
//

#if os(iOS)

import Charts
import SwiftUI
import UIKit

// MARK: - 레이아웃 스케일 (상세 화면 ↔ 공유 이미지 일치)

enum HikingRecordCardLayout {
    static let referenceContentWidth: CGFloat = 377
    static var referenceScreenWidth: CGFloat { referenceContentWidth + detailContentWidthInset }
    static let referenceViewportHeight: CGFloat = 780

    static let detailHorizontalPadding: CGFloat = 8
    static let detailContentWidthInset: CGFloat = 16
    static let detailTopPadding: CGFloat = 6
    /// 공유·저장 이미지 상단 `sansan` — 콘텐츠 너비 대비 글자 크기.
    static let exportBrandTitleFontRatio: CGFloat = 0.0468
    /// `[sansan]` 위 여백(기준 화면 너비 pt). 상태바 안전 영역은 캡처에서 제외합니다.
    static let exportBrandTitleTopPadding: CGFloat = 8
    static let detailBottomPadding: CGFloat = 10
    static let detailSectionSpacing: CGFloat = 10
    /// 시작/종료·시간/거리/상승 등 가로 나란한 카드 사이 간격.
    static let cardGridSpacing: CGFloat = 8
    /// 기록 상세 스크롤 화면 지도 높이 상한 (뷰포트 대비).
    static let detailMapMaxViewportFraction: CGFloat = 0.48
    /// ImageRenderer 높이 산정 여유 (차트 x축·푸터 잘림 방지).
    static let exportContentHeightBuffer: CGFloat = 36
    /// 공유·저장 카드 상단 제목 — 본문 한 줄 높이.
    static let exportTitlePrimarySize: CGFloat = 20
    static let exportTitleSecondarySize: CGFloat = 12
    static let exportTitleIconBox: CGFloat = 34
    static let exportTitleIconSymbol: CGFloat = 16
    static let detailTitleIconBox: CGFloat = 28
    static let detailTitleIconSymbol: CGFloat = 13
    static let exportTitleIconSpacing: CGFloat = 10
    static let exportTitleRowSpacing: CGFloat = 6
    static let detailTitleRowSpacing: CGFloat = 3
    /// 기록 상세 타이틀 카드 프로필 — 콘텐츠 높이 대비 축소 비율.
    static let detailTitleProfileAvatarScale: CGFloat = 0.88
    static let exportTitleMetaLeadingInset: CGFloat = exportTitleIconBox + exportTitleIconSpacing
    static let detailTitleMetaLeadingInset: CGFloat = detailTitleIconBox + exportTitleIconSpacing
    static let exportTitleWeatherIconSize: CGFloat = 20
    static let exportTitleWeatherTempSize: CGFloat = 13
    static let exportTitleWeatherLabelSize: CGFloat = 10
    static let exportTitleWeatherSpacing: CGFloat = 4
    static let exportTitleWeatherInlineSpacing: CGFloat = 5
    static let weatherTimelineIconSize: CGFloat = 20
    static let weatherTimelineTempSize: CGFloat = 13
    static let weatherTimelineStackSpacing: CGFloat = 4
    static let weatherOnFill = Color.white

    static func weatherCardFill(for colorScheme: ColorScheme) -> LinearGradient {
        let top: Color
        let bottom: Color
        if colorScheme == .dark {
            top = Color(red: 0.28, green: 0.50, blue: 0.30)
            bottom = Color(red: 0.16, green: 0.36, blue: 0.20)
        } else {
            top = Color(red: 0.36, green: 0.62, blue: 0.32)
            bottom = Color(red: 0.22, green: 0.46, blue: 0.24)
        }
        return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var weatherTimelineHeight: CGFloat {
        weatherTimelineIconSize
            + weatherTimelineStackSpacing
            + weatherTimelineTempSize
    }
    /// 사용자 지정 이름이 없을 때 공유·저장 카드 제목.
    static let exportDefaultRouteTitle = "[저장된 경로]"
    static let mapCornerRadius: CGFloat = 14
    static let exportOuterCornerRadius: CGFloat = 24

    static let cardCornerRadius: CGFloat = 14
    static let cardPadding: CGFloat = 11
    static let cardMinHeight: CGFloat = 78
    static let cardRowSpacing: CGFloat = 6
    static let cardLabelSize: CGFloat = 10
    static let cardPrimarySize: CGFloat = 22
    static let cardSecondarySize: CGFloat = 11
    /// 고도·심박 프로필 카드 헤더의 최고 고도·평균 심박 표시.
    static let cardProfileMetricValueSize: CGFloat = 13
    static let cardSuffixSize: CGFloat = 11
    /// grouped 배경 위의 카드. 다크 모드에서 `systemBackground`는 페이지와 같아져 윤곽이 사라집니다.
    static var groupedCardFill: Color {
        Color(.secondarySystemGroupedBackground)
    }

    static func groupedCardStroke(for colorScheme: ColorScheme) -> Color {
        Color.primary.opacity(colorScheme == .dark ? 0.2 : 0.08)
    }
    static let compactIconBox: CGFloat = 22
    static let compactIconSymbol: CGFloat = 11
    static let elevationChartHeight: CGFloat = 164
    /// `HikingElevationProfileCard` VStack spacing.
    static let elevationChartSectionSpacing: CGFloat = 10

    /// 기록 상세 `HikingRecordDetailView`·저장 이미지 공통 지도 높이.
    static func detailMapHeight(contentWidth: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        guard contentWidth > 0, viewportHeight > 0 else { return 0 }
        return min(
            contentWidth * 4 / 3,
            viewportHeight * detailMapMaxViewportFraction
        )
    }

    static func estimatedTitleHeaderHeight(
        scale: CGFloat,
        showsDateSubtitle: Bool,
        compact: Bool = false,
        showsProfileAvatar: Bool = false
    ) -> CGFloat {
        let padding = cardPadding * 2 * scale
        let rowSpacing = compact ? detailTitleRowSpacing : exportTitleRowSpacing
        let titleHeight = exportTitlePrimarySize * 2.2 * scale
        let leftBlock: CGFloat
        if showsProfileAvatar {
            if showsDateSubtitle {
                leftBlock = titleHeight
                    + rowSpacing * scale
                    + exportTitleSecondarySize * scale * 1.2
            } else {
                leftBlock = titleHeight
            }
        } else {
            let iconBox = compact ? detailTitleIconBox : exportTitleIconBox
            let primary = max(iconBox, titleHeight)
            if showsDateSubtitle {
                leftBlock = primary
                    + rowSpacing * scale
                    + exportTitleSecondarySize * scale * 1.2
            } else {
                leftBlock = primary
            }
        }
        return padding + leftBlock
    }

    static func estimatedWeatherCardHeight(scale: CGFloat) -> CGFloat {
        let pad = cardPadding * 2 * scale
        let header = compactIconBox * scale
        let spacing = cardRowSpacing * scale
        return pad + header + spacing + weatherTimelineHeight * scale
    }

    /// 요약 섹션의 메트릭 카드 행 개수 (`HikingRecordSummarySection`과 동기화).
    static let summaryMetricRowCount = 2

    static func estimatedElevationChartCardHeight(scale: CGFloat) -> CGFloat {
        let pad = cardPadding * 2 * scale
        let header = compactIconBox * scale
        let spacing = elevationChartSectionSpacing * scale
        let chart = elevationChartHeight * scale
        return pad + header + spacing + chart
    }

    static func estimatedSummaryHeight(scale: CGFloat) -> CGFloat {
        let sectionGap = cardGridSpacing * scale
        let schedule = cardMinHeight * scale
        let metricRows = CGFloat(summaryMetricRowCount) * cardMinHeight * scale
        let chartCard = estimatedElevationChartCardHeight(scale: scale)
        let footer = 24 * scale
        let itemCount = 3 + summaryMetricRowCount
        let gaps = CGFloat(itemCount - 1) * sectionGap
        return schedule + metricRows + chartCard + footer + gaps
    }
}

private struct RecordCardLayoutScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var recordCardLayoutScale: CGFloat {
        get { self[RecordCardLayoutScaleKey.self] }
        set { self[RecordCardLayoutScaleKey.self] = newValue }
    }
}

extension CGFloat {
    func recordScaled(_ scale: CGFloat) -> CGFloat { self * scale }
}

extension BinaryInteger {
    func recordScaled(_ scale: CGFloat) -> CGFloat { CGFloat(self) * scale }
}

// MARK: - 제목 카드 (상세·공유 공통)

struct HikingRecordTitleCard: View {
    let record: SavedHikingSession
    var layoutScale: CGFloat = 1
    /// 기록 상세 — 아이콘·제목/일정 간격을 조금 더 촘촘하게.
    var compact: Bool = false
    /// 기록 상세 — 등산 아이콘 대신 프로필 이미지.
    var showsProfileAvatar: Bool = false
    /// 기록 상세 — 제목 아래 메모 입력.
    var isMemoEditable: Bool = false
    var onMemoCommit: ((String) -> Void)? = nil

    @ObservedObject private var profilePhoto = UserProfilePhotoObserver.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var memoDraft: String
    @State private var showsMemoSheet = false

    init(
        record: SavedHikingSession,
        layoutScale: CGFloat = 1,
        compact: Bool = false,
        showsProfileAvatar: Bool = false,
        isMemoEditable: Bool = false,
        onMemoCommit: ((String) -> Void)? = nil
    ) {
        self.record = record
        self.layoutScale = layoutScale
        self.compact = compact
        self.showsProfileAvatar = showsProfileAvatar
        self.isMemoEditable = isMemoEditable
        self.onMemoCommit = onMemoCommit
        _memoDraft = State(initialValue: record.memo ?? "")
    }

    private var routeTint: Color {
        Color(red: 0.12, green: 0.72, blue: 0.45)
    }

    private var titleText: String {
        record.exportCardTitle
    }

    private var iconBox: CGFloat {
        let base = compact
            ? HikingRecordCardLayout.detailTitleIconBox
            : HikingRecordCardLayout.exportTitleIconBox
        return base * layoutScale
    }

    private var iconSymbolSize: CGFloat {
        let base = compact
            ? HikingRecordCardLayout.detailTitleIconSymbol
            : HikingRecordCardLayout.exportTitleIconSymbol
        return base * layoutScale
    }

    private var titleScheduleSpacing: CGFloat {
        let base = compact
            ? HikingRecordCardLayout.detailTitleRowSpacing
            : HikingRecordCardLayout.exportTitleRowSpacing
        return base * layoutScale
    }

    private var metaLeadingInset: CGFloat {
        let base = compact
            ? HikingRecordCardLayout.detailTitleMetaLeadingInset
            : HikingRecordCardLayout.exportTitleMetaLeadingInset
        return base * layoutScale
    }

    private var showsMemoSubtitle: Bool {
        isMemoEditable || !(record.memo?.isEmpty ?? true)
    }

    private var titleCardContentHeight: CGFloat {
        let titleHeight = HikingRecordCardLayout.exportTitlePrimarySize * layoutScale * 2.2
        let scheduleHeight = HikingRecordCardLayout.exportTitleSecondarySize * layoutScale * 1.2
        return titleHeight + (
            showsMemoSubtitle ? titleScheduleSpacing + scheduleHeight : 0
        )
    }

    var body: some View {
        let radius = HikingRecordCardLayout.cardCornerRadius * layoutScale
        let padding = HikingRecordCardLayout.cardPadding * layoutScale

        Group {
            if showsProfileAvatar {
                profileAvatarTitleContent
            } else {
                hikingIconTitleContent
            }
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HikingRecordCardLayout.groupedCardFill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(HikingRecordCardLayout.groupedCardStroke(for: colorScheme), lineWidth: 0.5)
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.28 : 0.05),
            radius: 8 * layoutScale,
            y: 3 * layoutScale
        )
        .modifier(TitleCardAccessibilityModifier(
            isMemoEditable: isMemoEditable,
            accessibilityText: accessibilityText
        ))
        .onAppear {
            memoDraft = record.memo ?? ""
        }
        .onChange(of: record.memo) { _, newValue in
            guard !showsMemoSheet else { return }
            memoDraft = newValue ?? ""
        }
        .sheet(isPresented: $showsMemoSheet) {
            RecordMemoSheet(
                draft: $memoDraft,
                onSave: saveMemoFromSheet,
                onCancel: cancelMemoSheet
            )
        }
    }

    private var hikingIconTitleContent: some View {
        HStack(alignment: .center, spacing: 10 * layoutScale) {
            VStack(alignment: .leading, spacing: titleScheduleSpacing) {
                HStack(alignment: .center, spacing: HikingRecordCardLayout.exportTitleIconSpacing * layoutScale) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8 * layoutScale, style: .continuous)
                            .fill(routeTint.opacity(0.14))
                        Image(systemName: "figure.hiking")
                            .font(.system(
                                size: iconSymbolSize,
                                weight: .semibold
                            ))
                            .foregroundStyle(routeTint)
                    }
                    .frame(width: iconBox, height: iconBox)
                    .accessibilityHidden(true)

                    Text(titleText)
                        .font(.system(
                            size: HikingRecordCardLayout.exportTitlePrimarySize * layoutScale,
                            weight: .semibold,
                            design: .rounded
                        ))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.88)
                }

                titleMemoSubtitle
                    .padding(.leading, metaLeadingInset)
            }

            Spacer(minLength: 0)
        }
    }

    private var profileAvatarTitleContent: some View {
        HStack(alignment: .center, spacing: HikingRecordCardLayout.exportTitleIconSpacing * layoutScale) {
            titleCardProfileAvatar

            VStack(alignment: .leading, spacing: titleScheduleSpacing) {
                Text(titleText)
                    .font(.system(
                        size: HikingRecordCardLayout.exportTitlePrimarySize * layoutScale,
                        weight: .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)

                titleMemoSubtitle
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var titleMemoSubtitle: some View {
        let font = Font.system(
            size: HikingRecordCardLayout.exportTitleSecondarySize * layoutScale,
            weight: .medium
        )

        if isMemoEditable {
            Button {
                memoDraft = record.memo ?? ""
                showsMemoSheet = true
            } label: {
                Text(memoEditableLabel)
                    .font(font)
                    .foregroundStyle(memoEditableLabelColor)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(memoAccessibilityLabel)
            .accessibilityHint("두 번 탭하여 메모를 수정합니다.")
        } else if let memo = record.memo, !memo.isEmpty {
            Text(memo)
                .font(font)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .minimumScaleFactor(0.9)
        }
    }

    private var memoEditableLabel: String {
        let memo = record.memo ?? ""
        return memo.isEmpty ? "메모를 입력하세요" : memo
    }

    private var memoEditableLabelColor: Color {
        (record.memo?.isEmpty ?? true) ? Color(.tertiaryLabel) : .secondary
    }

    private var memoAccessibilityLabel: String {
        let memo = record.memo ?? ""
        return memo.isEmpty ? "메모 없음" : memo
    }

    private func saveMemoFromSheet() {
        guard isMemoEditable else { return }
        let normalized = SavedHikingSession.normalizedMemo(memoDraft)
        let stored = record.memo
        if normalized != stored {
            onMemoCommit?(memoDraft)
        }
        memoDraft = normalized ?? ""
        showsMemoSheet = false
    }

    private func cancelMemoSheet() {
        memoDraft = record.memo ?? ""
        showsMemoSheet = false
    }

    private var titleCardProfileAvatarSide: CGFloat {
        titleCardContentHeight * HikingRecordCardLayout.detailTitleProfileAvatarScale
    }

    @ViewBuilder
    private var titleCardProfileAvatar: some View {
        let side = titleCardProfileAvatarSide

        Group {
            if let image = profilePhoto.displayImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(Color(.secondarySystemGroupedBackground))
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: side * 0.52, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityLabel("프로필 아바타")
    }

    private var accessibilityText: String {
        let memoPart = record.memo.map { ", \($0)" } ?? ""
        return "\(titleText)\(memoPart)"
    }
}

private struct TitleCardAccessibilityModifier: ViewModifier {
    let isMemoEditable: Bool
    let accessibilityText: String

    func body(content: Content) -> some View {
        if isMemoEditable {
            content.accessibilityElement(children: .contain)
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityText)
        }
    }
}

struct HikingRecordWeatherCard: View {
    let weather: HikingRouteWeatherSnapshot
    var layoutScale: CGFloat = 1

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pad = HikingRecordCardLayout.cardPadding.recordScaled(layoutScale)
        let rowGap = HikingRecordCardLayout.cardRowSpacing.recordScaled(layoutScale)
        let headerHeight = HikingRecordCardLayout.compactIconBox.recordScaled(layoutScale)
        let radius = HikingRecordCardLayout.cardCornerRadius.recordScaled(layoutScale)
        let onFill = HikingRecordCardLayout.weatherOnFill

        VStack(alignment: .leading, spacing: rowGap) {
            HStack(alignment: .center, spacing: 5.recordScaled(layoutScale)) {
                RecordSummaryCardIcon(
                    icon: "cloud.sun.fill",
                    tint: onFill,
                    layoutScale: layoutScale
                )

                Text("날씨")
                    .font(.system(
                        size: HikingRecordCardLayout.cardLabelSize.recordScaled(layoutScale),
                        weight: .semibold
                    ))
                    .foregroundStyle(onFill.opacity(0.86))
                    .lineLimit(1)
            }
            .frame(height: headerHeight, alignment: .center)

            HikingRecordWeatherTimeline(weather: weather, layoutScale: layoutScale)
                .frame(maxWidth: .infinity)
        }
        .padding(pad)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            HikingRecordCardLayout.weatherCardFill(for: colorScheme),
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(onFill.opacity(colorScheme == .dark ? 0.16 : 0.12), lineWidth: 0.5)
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.32 : 0.08),
            radius: 8.recordScaled(layoutScale),
            y: 3.recordScaled(layoutScale)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("날씨")
    }
}

struct HikingRecordWeatherTimeline: View {
    let weather: HikingRouteWeatherSnapshot
    var layoutScale: CGFloat = 1

    private var hours: [HikingWeatherHourPoint] {
        weather.timelineHours
    }

    var body: some View {
        let columns = displayedHours
        if shouldScroll(columnCount: columns.count) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8 * layoutScale) {
                    ForEach(columns) { hour in
                        hourColumn(hour)
                            .frame(width: 48 * layoutScale)
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                ForEach(columns) { hour in
                    hourColumn(hour)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var displayedHours: [HikingWeatherHourPoint] {
        let all = hours
        guard layoutScale > 1, all.count > 8 else { return all }
        return Self.sampledHours(all, maxCount: 8)
    }

    private func shouldScroll(columnCount: Int) -> Bool {
        layoutScale <= 1 && columnCount > 8
    }

    private static func sampledHours(
        _ hours: [HikingWeatherHourPoint],
        maxCount: Int
    ) -> [HikingWeatherHourPoint] {
        guard hours.count > maxCount, maxCount > 1 else { return hours }
        let lastIndex = hours.count - 1
        var picked: [HikingWeatherHourPoint] = []
        picked.reserveCapacity(maxCount)
        for i in 0..<maxCount {
            let index = Int(round(Double(i) * Double(lastIndex) / Double(maxCount - 1)))
            if picked.last?.date != hours[index].date {
                picked.append(hours[index])
            }
        }
        return picked
    }

    private func hourColumn(_ hour: HikingWeatherHourPoint) -> some View {
        VStack(spacing: HikingRecordCardLayout.weatherTimelineStackSpacing * layoutScale) {
            Image(systemName: HikingRouteWeatherSnapshot.symbolName(for: hour.wmoCode))
                .font(.system(
                    size: HikingRecordCardLayout.weatherTimelineIconSize * layoutScale,
                    weight: .semibold
                ))
                .foregroundStyle(HikingRecordCardLayout.weatherOnFill)
                .symbolRenderingMode(.hierarchical)
                .frame(height: HikingRecordCardLayout.weatherTimelineIconSize * layoutScale)

            Text(hour.formattedTemperature)
                .font(.system(
                    size: HikingRecordCardLayout.weatherTimelineTempSize * layoutScale,
                    weight: .semibold,
                    design: .rounded
                ))
                .foregroundStyle(HikingRecordCardLayout.weatherOnFill)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(HikingRouteWeatherSnapshot.conditionLabel(for: hour.wmoCode)), \(hour.formattedTemperature)"
        )
    }
}

// MARK: - 공통 카드 크롬

private struct RecordSummaryCardChrome: ViewModifier {
    @Environment(\.recordCardLayoutScale) private var layoutScale
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let radius = HikingRecordCardLayout.cardCornerRadius.recordScaled(layoutScale)

        content
            .background(
                HikingRecordCardLayout.groupedCardFill,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(HikingRecordCardLayout.groupedCardStroke(for: colorScheme), lineWidth: 0.5)
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.28 : 0.05),
                radius: 8.recordScaled(layoutScale),
                y: 3.recordScaled(layoutScale)
            )
    }
}

private extension View {
    func recordSummaryCardChrome() -> some View {
        modifier(RecordSummaryCardChrome())
    }
}

// MARK: - 통일 메트릭 카드

/// 시작·종료·시간·거리·상승 — 동일한 3단 구조(라벨 / 주요값 / 보조).
private struct RecordSummaryMetricCard: View {
    @Environment(\.recordCardLayoutScale) private var layoutScale

    let label: String
    let primaryText: String
    var primarySuffix: String? = nil
    var secondaryText: String? = nil
    let icon: String
    let tint: Color

    var body: some View {
        let pad = HikingRecordCardLayout.cardPadding.recordScaled(layoutScale)
        let rowGap = HikingRecordCardLayout.cardRowSpacing.recordScaled(layoutScale)

        VStack(alignment: .leading, spacing: rowGap) {
            HStack(spacing: 5.recordScaled(layoutScale)) {
                cardIcon

                Text(label)
                    .font(.system(
                        size: HikingRecordCardLayout.cardLabelSize.recordScaled(layoutScale),
                        weight: .semibold
                    ))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3.recordScaled(layoutScale)) {
                Spacer(minLength: 0)

                Text(primaryText)
                    .font(.system(
                        size: HikingRecordCardLayout.cardPrimarySize.recordScaled(layoutScale),
                        weight: .bold,
                        design: .rounded
                    ))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .allowsTightening(true)

                if let primarySuffix, !primarySuffix.isEmpty {
                    Text(primarySuffix)
                        .font(.system(
                            size: HikingRecordCardLayout.cardSuffixSize.recordScaled(layoutScale),
                            weight: .medium
                        ))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let secondaryText, !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(.system(
                        size: HikingRecordCardLayout.cardSecondarySize.recordScaled(layoutScale),
                        weight: .medium
                    ))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(pad)
        .frame(
            maxWidth: .infinity,
            minHeight: HikingRecordCardLayout.cardMinHeight.recordScaled(layoutScale),
            alignment: .topLeading
        )
        .recordSummaryCardChrome()
    }

    private var cardIcon: some View {
        RecordSummaryCardIcon(icon: icon, tint: tint, layoutScale: layoutScale)
    }
}

/// 시작·종료 카드 — 1행: 아이콘·라벨 + 날짜(우측), 2행: 시간·오전/오후(우측).
private struct RecordScheduleMetricCard: View {
    @Environment(\.recordCardLayoutScale) private var layoutScale

    let label: String
    let parts: ScheduleDateParts
    let icon: String
    let tint: Color

    var body: some View {
        let pad = HikingRecordCardLayout.cardPadding.recordScaled(layoutScale)
        let rowGap = HikingRecordCardLayout.cardRowSpacing.recordScaled(layoutScale)
        let headerHeight = HikingRecordCardLayout.compactIconBox.recordScaled(layoutScale)

        VStack(alignment: .leading, spacing: rowGap) {
            HStack(alignment: .center, spacing: 5.recordScaled(layoutScale)) {
                RecordSummaryCardIcon(icon: icon, tint: tint, layoutScale: layoutScale)

                Text(label)
                    .font(.system(
                        size: HikingRecordCardLayout.cardLabelSize.recordScaled(layoutScale),
                        weight: .semibold
                    ))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4.recordScaled(layoutScale))

                Text(parts.dateText)
                    .font(.system(
                        size: HikingRecordCardLayout.cardSecondarySize.recordScaled(layoutScale),
                        weight: .medium
                    ))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            }
            .frame(height: headerHeight, alignment: .center)

            HStack(alignment: .firstTextBaseline, spacing: 3.recordScaled(layoutScale)) {
                Spacer(minLength: 0)

                Text(parts.timeText)
                    .font(.system(
                        size: HikingRecordCardLayout.cardPrimarySize.recordScaled(layoutScale),
                        weight: .bold,
                        design: .rounded
                    ))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .allowsTightening(true)

                if let periodText = parts.periodText, !periodText.isEmpty {
                    Text(periodText)
                        .font(.system(
                            size: HikingRecordCardLayout.cardSuffixSize.recordScaled(layoutScale),
                            weight: .medium
                        ))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(pad)
        .frame(
            maxWidth: .infinity,
            minHeight: HikingRecordCardLayout.cardMinHeight.recordScaled(layoutScale),
            alignment: .topLeading
        )
        .recordSummaryCardChrome()
    }
}

private struct RecordSummaryCardIcon: View {
    let icon: String
    let tint: Color
    let layoutScale: CGFloat

    var body: some View {
        let box = HikingRecordCardLayout.compactIconBox.recordScaled(layoutScale)
        let radius = 6.recordScaled(layoutScale)

        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(tint.opacity(0.12))
            .frame(width: box, height: box)
            .overlay {
                Image(systemName: icon)
                    .font(.system(
                        size: HikingRecordCardLayout.compactIconSymbol.recordScaled(layoutScale),
                        weight: .semibold
                    ))
                    .foregroundStyle(tint)
            }
    }
}

// MARK: - 고도 프로필

private struct ElevationProfileChartPoint: Identifiable {
    let id: UUID
    let distanceKilometers: Double
    let altitude: Double
}

private struct HeartRateProfileChartPoint: Identifiable {
    let id: UUID
    let distanceKilometers: Double
    let bpm: Double
}

/// GPS 포인트 부족 시 시간 축 심박 차트용 샘플.
private struct TimeHeartRateChartPoint: Identifiable {
    let id: UUID
    let elapsedMinutes: Double
    let bpm: Double
}

private struct ProfileDistanceAxisSpec {
    let domain: ClosedRange<Double>
    let ticks: [Double]

    static func make(maxKilometers: Double) -> ProfileDistanceAxisSpec {
        guard maxKilometers > 0 else {
            return make(ceiling: 1, step: 0.2)
        }

        if maxKilometers < 1 {
            return make(ceiling: 1, step: 0.2)
        }
        if maxKilometers < 2 {
            return make(ceiling: 2, step: 0.5)
        }
        if maxKilometers < 3 {
            return make(ceiling: 3, step: 0.5)
        }
        if maxKilometers < 4 {
            return make(ceiling: 4, step: 1)
        }
        if maxKilometers < 5 {
            return make(ceiling: 5, step: 1)
        }

        let ceilingKilometers = Int(ceil(maxKilometers))
        let stepKilometers = kilometerStep(for: ceilingKilometers)
        return make(ceiling: Double(ceilingKilometers), step: Double(stepKilometers))
    }

    private static func make(ceiling: Double, step: Double) -> ProfileDistanceAxisSpec {
        let safeCeiling = max(ceiling, step)
        let safeStep = max(step, 0.01)
        var ticks: [Double] = [0]
        var value = safeStep
        while value < safeCeiling - 0.0001 {
            ticks.append((value * 1000).rounded() / 1000)
            value += safeStep
        }
        let roundedCeiling = (safeCeiling * 1000).rounded() / 1000
        if ticks.last != roundedCeiling {
            ticks.append(roundedCeiling)
        }
        return ProfileDistanceAxisSpec(domain: 0...roundedCeiling, ticks: ticks)
    }

    /// 거리 상한(km)에 맞춰 1·2·5·10 km 단위로 눈금 간격을 선택합니다.
    private static func kilometerStep(for ceilingKilometers: Int) -> Int {
        switch ceilingKilometers {
        case ...10:
            return 1
        case ...20:
            return 2
        case ...50:
            return 5
        case ...100:
            return 10
        default:
            let rough = Double(ceilingKilometers) / 10
            if rough <= 20 { return 20 }
            if rough <= 50 { return 50 }
            return Int(ceil(rough / 100) * 100)
        }
    }
}

private struct ProfileAxisSpec {
    let domain: ClosedRange<Double>
    let ticks: [Int]

    static func elevation(maxAltitude: Double) -> ProfileAxisSpec {
        let maximum = max(0, maxAltitude)

        if maximum < 40 {
            return ProfileAxisSpec(domain: 0...40, ticks: [0, 10, 20, 30, 40])
        }
        if maximum < 80 {
            return ProfileAxisSpec(domain: 0...80, ticks: [0, 20, 40, 60, 80])
        }
        if maximum < 200 {
            return ProfileAxisSpec(domain: 0...200, ticks: [0, 50, 100, 150, 200])
        }
        if maximum < 500 {
            return ProfileAxisSpec(domain: 0...500, ticks: [0, 100, 200, 300, 400, 500])
        }

        let ceiling = ceil(maximum / 500) * 500
        let tickCount = Int(ceiling / 500) + 1
        let ticks = (0..<tickCount).map { $0 * 500 }
        return ProfileAxisSpec(domain: 0...ceiling, ticks: ticks)
    }

    static func heartRate(maxBPM: Double) -> ProfileAxisSpec {
        if maxBPM < 160 {
            return ProfileAxisSpec(domain: 40...160, ticks: [40, 70, 100, 130, 160])
        }
        if maxBPM < 200 {
            return ProfileAxisSpec(domain: 40...240, ticks: [40, 90, 140, 190, 240])
        }

        let minimumSpan = maxBPM - 40
        let ceiling = 40 + ceil(minimumSpan / 50) * 50
        var ticks = [40]
        while Double(ticks.last ?? 40) + 50 <= ceiling {
            ticks.append((ticks.last ?? 40) + 50)
        }
        if ticks.last.map({ Double($0) }) != ceiling {
            ticks.append(Int(ceiling))
        }
        return ProfileAxisSpec(domain: 40...ceiling, ticks: ticks)
    }
}

private enum ElevationProfileActiveMetric {
    case elevation
    case heartRate
}

struct HikingElevationProfileCard: View {
    @Environment(\.recordCardLayoutScale) private var layoutScale

    let points: [HikingPoint]
    var heartRateSamples: [HikingHeartRateSample] = []
    /// 저장 시 계산해 둔 프로필 — 있으면 열 때 재계산하지 않습니다.
    var persistedElevationProfile: [HikingElevationChartSample]? = nil
    var persistedHeartRateProfile: [HikingHeartRateChartSample]? = nil

    @State private var activeMetric: ElevationProfileActiveMetric = .elevation
    @State private var preparedChartPoints: [ElevationProfileChartPoint] = []
    @State private var preparedHeartRateChartPoints: [HeartRateProfileChartPoint] = []
    @State private var isChartDataReady = false
    @State private var isScrubbingChart = false
    @State private var scrubbedDistanceKilometers: Double?
    @State private var lastScrubHapticSampleIndex: Int?

    private static let inactiveLineColor = Color.gray.opacity(0.38)
    private static let inactiveAreaColor = Color.gray.opacity(0.08)
    private static let elevationBaseline: Double = 0
    private static let heartRateBaseline: Double = 40
    private static let yAxisLegendMinimumWidth: CGFloat = 28
    /// Y·X축 눈금 공통 — 기본 10pt의 80%.
    private static let axisTickFontSize: CGFloat = 8
    /// Y축 눈금 열과 그래프 사이 고정 간격.
    private static let yAxisGraphGap: CGFloat = 4
    private static let xAxisRowHeight: CGFloat = 14
    private static let plotXAxisGap: CGFloat = 2
    private static let chartBottomPadding: CGFloat = 2

    private var chartPoints: [ElevationProfileChartPoint] {
        preparedChartPoints
    }

    private var heartRateChartPoints: [HeartRateProfileChartPoint] {
        preparedHeartRateChartPoints
    }

    private var hasPersistedChartData: Bool {
        persistedElevationProfile != nil
    }

    private var chartPreparationToken: String {
        let pointSignature = points.prefix(3).map(\.id.uuidString).joined(separator: ",")
        let heartRateSignature = heartRateSamples.prefix(3).map(\.id.uuidString).joined(separator: ",")
        return "\(points.count)|\(heartRateSamples.count)|\(pointSignature)|\(heartRateSignature)"
    }

    private var showsHeartRateOverlay: Bool {
        heartRateChartPoints.count >= 2
    }

    /// GPS 포인트 부족으로 거리 축 프로필을 만들 수 없지만 심박 기록은 있는 경우 —
    /// 심박 차트를 시간 축으로 대체 표시합니다.
    private var isTimeBasedHeartRateFallback: Bool {
        points.count < 2 && !hasPersistedChartData && heartRateSamples.count >= 2
    }

    private var timeBasedHeartRatePoints: [TimeHeartRateChartPoint] {
        let sorted = heartRateSamples.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first else { return [] }
        return sorted.map { sample in
            TimeHeartRateChartPoint(
                id: sample.id,
                elapsedMinutes: sample.timestamp.timeIntervalSince(first.timestamp) / 60,
                bpm: sample.bpm
            )
        }
    }

    private var fallbackHeartRateStats: (average: Int, minimum: Int, maximum: Int)? {
        let bpms = heartRateSamples.map(\.bpm)
        guard !bpms.isEmpty, let minValue = bpms.min(), let maxValue = bpms.max() else { return nil }
        let average = bpms.reduce(0, +) / Double(bpms.count)
        return (Int(average.rounded()), Int(minValue.rounded()), Int(maxValue.rounded()))
    }

    private var chartHeight: CGFloat {
        HikingRecordCardLayout.elevationChartHeight.recordScaled(layoutScale)
    }

    private var xAxisRowHeight: CGFloat {
        Self.xAxisRowHeight.recordScaled(layoutScale)
    }

    private var plotXAxisGap: CGFloat {
        Self.plotXAxisGap.recordScaled(layoutScale)
    }

    private var chartBottomPadding: CGFloat {
        Self.chartBottomPadding.recordScaled(layoutScale)
    }

    private var plotAreaHeight: CGFloat {
        max(chartHeight - xAxisRowHeight - plotXAxisGap - chartBottomPadding, 0)
    }

    /// 표준 축 배치: 최저 눈금(0)은 맨 아래, 최고 눈금은 맨 위. 그래프는 전체 높이를 채웁니다.
    /// 상·하단 스트로크가 잘리지 않을 만큼만 작은 여백을 두고, 범례·차트가 동일 값으로 사용해
    /// 눈금과 그래프 값이 정확히 정렬됩니다.
    private var plotEdgeInset: CGFloat {
        2.recordScaled(layoutScale)
    }

    private var elevationAxisSpec: ProfileAxisSpec {
        ProfileAxisSpec.elevation(maxAltitude: preparedChartPoints.map(\.altitude).max() ?? 0)
    }

    private var heartRateAxisSpec: ProfileAxisSpec {
        let maxBPM: Double
        if isTimeBasedHeartRateFallback {
            maxBPM = heartRateSamples.map(\.bpm).max() ?? Self.heartRateBaseline
        } else {
            maxBPM = preparedHeartRateChartPoints.map(\.bpm).max() ?? Self.heartRateBaseline
        }
        return ProfileAxisSpec.heartRate(maxBPM: maxBPM)
    }

    private var chartLoadingPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.04))
            .overlay {
                ProgressView()
            }
    }

    /// GPS 포인트 없이 심박만 있는 기록 — 경과 시간(분) 축 심박 차트.
    private var timeBasedHeartRateChart: some View {
        Chart(timeBasedHeartRatePoints) { point in
            LineMark(
                x: .value("시간", point.elapsedMinutes),
                y: .value("심박", point.bpm)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.red.gradient)

            AreaMark(
                x: .value("시간", point.elapsedMinutes),
                yStart: .value("기준", Self.heartRateBaseline),
                yEnd: .value("심박", point.bpm)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.red.opacity(0.12))
        }
        .chartYScale(domain: heartRateYDomain)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let bpm = value.as(Double.self) {
                        Text("\(Int(bpm))")
                            .font(.system(size: Self.axisTickFontSize.recordScaled(layoutScale)))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text("\(Int(minutes))분")
                            .font(.system(size: Self.axisTickFontSize.recordScaled(layoutScale)))
                    }
                }
            }
        }
    }

    private func loadPersistedChartDataIfAvailable() -> Bool {
        guard let persistedElevationProfile else { return false }
        preparedChartPoints = persistedElevationProfile.map { sample in
            ElevationProfileChartPoint(
                id: sample.id,
                distanceKilometers: sample.distanceMeters / 1_000,
                altitude: sample.altitude
            )
        }
        preparedHeartRateChartPoints = (persistedHeartRateProfile ?? []).map { sample in
            HeartRateProfileChartPoint(
                id: sample.id,
                distanceKilometers: sample.distanceMeters / 1_000,
                bpm: sample.bpm
            )
        }
        isChartDataReady = true
        return true
    }

    private func prepareChartData() async {
        if loadPersistedChartDataIfAvailable() { return }

        isChartDataReady = false

        let sourcePoints = points
        let sourceHeartRateSamples = heartRateSamples

        let prepared = await Task.detached(priority: .userInitiated) {
            let elevation = HikingSessionMetrics.elevationProfileSamples(from: sourcePoints).map { sample in
                ElevationProfileChartPoint(
                    id: sample.id,
                    distanceKilometers: sample.distanceMeters / 1_000,
                    altitude: sample.altitude
                )
            }
            let heartRate = HikingSessionMetrics.heartRateProfileSamples(
                from: sourcePoints,
                heartRateSamples: sourceHeartRateSamples
            ).map { sample in
                HeartRateProfileChartPoint(
                    id: sample.id,
                    distanceKilometers: sample.distanceMeters / 1_000,
                    bpm: sample.bpm
                )
            }
            return (elevation, heartRate)
        }.value

        preparedChartPoints = prepared.0
        preparedHeartRateChartPoints = prepared.1
        isChartDataReady = true
    }

    private var yAxisTickLabelBandWidth: CGFloat {
        let fontSize = Self.axisTickFontSize.recordScaled(layoutScale)
        let allTicks = elevationYTickValues + (showsHeartRateOverlay ? heartRateYTickValues : [])
        let longestDigitCount = allTicks.map { String($0).count }.max() ?? 1
        let textWidth = CGFloat(longestDigitCount) * fontSize * 0.72
        let minimum = Self.yAxisLegendMinimumWidth.recordScaled(layoutScale) * 0.8
        return max(minimum, textWidth + 4.recordScaled(layoutScale))
    }

    /// 좌·우 Y축 열 너비 — 눈금 밴드 폭을 동일하게 맞춥니다.
    private var sharedYAxisColumnWidth: CGFloat {
        yAxisTickLabelBandWidth
    }

    private var yAxisGraphGap: CGFloat {
        Self.yAxisGraphGap.recordScaled(layoutScale)
    }

    var body: some View {
        let pad = HikingRecordCardLayout.cardPadding.recordScaled(layoutScale)

        VStack(alignment: .leading, spacing: 10.recordScaled(layoutScale)) {
            headerRow

            if isChartDataReady, chartPoints.count >= 2 {
                profileChart
                    .frame(height: chartHeight)
            } else if !isTimeBasedHeartRateFallback, hasPersistedChartData || points.count >= 2 {
                chartLoadingPlaceholder
                    .frame(height: chartHeight)
                    .task(id: chartPreparationToken) {
                        await prepareChartData()
                    }
            } else if isTimeBasedHeartRateFallback {
                timeBasedHeartRateChart
                    .frame(height: chartHeight)
            } else {
                ContentUnavailableView(
                    "고도 데이터 없음",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("GPS 포인트가 부족합니다.")
                )
                .frame(height: chartHeight)
            }
        }
        .padding(pad)
        .recordSummaryCardChrome()
    }

    private var headerIconSystemName: String {
        if isTimeBasedHeartRateFallback { return "heart.fill" }
        return showsHeartRateOverlay && activeMetric == .heartRate
            ? "heart.fill"
            : "chart.xyaxis.line"
    }

    private var headerIconTint: Color {
        if isTimeBasedHeartRateFallback { return .red }
        return showsHeartRateOverlay && activeMetric == .heartRate ? .red : .orange
    }

    private var headerAccessibilityLabel: String {
        if isTimeBasedHeartRateFallback { return "심박 기록" }
        if showsHeartRateOverlay, activeMetric == .heartRate {
            return "심박 프로필"
        }
        return "고도 프로필"
    }

    private var headerRow: some View {
        HStack(spacing: 5.recordScaled(layoutScale)) {
            RoundedRectangle(cornerRadius: 6.recordScaled(layoutScale), style: .continuous)
                .fill(headerIconTint.opacity(0.12))
                .frame(
                    width: HikingRecordCardLayout.compactIconBox.recordScaled(layoutScale),
                    height: HikingRecordCardLayout.compactIconBox.recordScaled(layoutScale)
                )
                .overlay {
                    Image(systemName: headerIconSystemName)
                        .font(.system(
                            size: HikingRecordCardLayout.compactIconSymbol.recordScaled(layoutScale),
                            weight: .semibold
                        ))
                        .foregroundStyle(headerIconTint)
                }
                .accessibilityLabel(headerAccessibilityLabel)

            if isTimeBasedHeartRateFallback {
                Text("심박")
                    .font(.system(
                        size: HikingRecordCardLayout.cardSecondarySize.recordScaled(layoutScale),
                        weight: .semibold
                    ))
                    .foregroundStyle(.red)
                    .padding(.leading, 4.recordScaled(layoutScale))
            } else if showsHeartRateOverlay {
                metricSelector
            } else {
                Text("고도")
                    .font(.system(
                        size: HikingRecordCardLayout.cardSecondarySize.recordScaled(layoutScale),
                        weight: .semibold
                    ))
                    .foregroundStyle(.orange)
                    .padding(.leading, 4.recordScaled(layoutScale))
            }

            Spacer()

            headerValueLabel
        }
    }

    private var metricSelector: some View {
        HStack(spacing: 6.recordScaled(layoutScale)) {
            metricChip(
                title: "고도",
                color: .orange,
                metric: .elevation
            )
            metricChip(
                title: "심박",
                color: .red,
                metric: .heartRate
            )
        }
        .padding(.leading, 4.recordScaled(layoutScale))
    }

    private func metricChip(
        title: String,
        color: Color,
        metric: ElevationProfileActiveMetric
    ) -> some View {
        let isActive = activeMetric == metric

        return Button {
            setActiveMetric(metric)
        } label: {
            HStack(spacing: 4.recordScaled(layoutScale)) {
                Circle()
                    .fill(isActive ? color : Self.inactiveLineColor)
                    .frame(
                        width: 6.recordScaled(layoutScale),
                        height: 6.recordScaled(layoutScale)
                    )
                Text(title)
                    .font(.system(
                        size: HikingRecordCardLayout.cardSecondarySize.recordScaled(layoutScale),
                        weight: isActive ? .semibold : .medium
                    ))
                    .foregroundStyle(isActive ? AnyShapeStyle(color) : AnyShapeStyle(.tertiary))
            }
        }
        .buttonStyle(.plain)
    }

    private var maxElevationMeters: Int {
        Int((chartPoints.map(\.altitude).max() ?? 0).rounded())
    }

    private var averageHeartRateBPM: Int? {
        guard !heartRateChartPoints.isEmpty else { return nil }
        let total = heartRateChartPoints.map(\.bpm).reduce(0, +)
        return Int((total / Double(heartRateChartPoints.count)).rounded())
    }

    private var minHeartRateBPM: Int? {
        guard let value = heartRateChartPoints.map(\.bpm).min() else { return nil }
        return Int(value.rounded())
    }

    private var maxHeartRateBPM: Int? {
        guard let value = heartRateChartPoints.map(\.bpm).max() else { return nil }
        return Int(value.rounded())
    }

    private func heartRateStatLabel(
        _ title: String,
        _ value: Int,
        showsUnit: Bool = false
    ) -> some View {
        HStack(spacing: 2.recordScaled(layoutScale)) {
            Text(title)
                .font(.system(
                    size: HikingRecordCardLayout.cardLabelSize.recordScaled(layoutScale),
                    weight: .medium
                ))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(
                    size: HikingRecordCardLayout.cardProfileMetricValueSize.recordScaled(layoutScale),
                    weight: .semibold
                ))
                .foregroundStyle(.red)
                .monospacedDigit()
            if showsUnit {
                Text("bpm")
                    .font(.system(
                        size: HikingRecordCardLayout.cardLabelSize.recordScaled(layoutScale),
                        weight: .medium
                    ))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var headerValueLabel: some View {
        if isTimeBasedHeartRateFallback {
            if let stats = fallbackHeartRateStats {
                HStack(spacing: 7.recordScaled(layoutScale)) {
                    heartRateStatLabel("평균", stats.average)
                    heartRateStatLabel("최저", stats.minimum)
                    heartRateStatLabel("최고", stats.maximum, showsUnit: true)
                }
                .fixedSize()
            }
        } else if showsHeartRateOverlay, activeMetric == .heartRate {
            if isScrubbingChart,
               let distance = scrubbedDistanceKilometers,
               let bpm = heartRate(at: distance) {
                Text("\(Int(bpm.rounded())) bpm")
                    .font(.system(
                        size: HikingRecordCardLayout.cardSecondarySize.recordScaled(layoutScale),
                        weight: .medium
                    ))
                    .foregroundStyle(.red)
                    .monospacedDigit()
            } else if let averageHeartRateBPM {
                HStack(spacing: 7.recordScaled(layoutScale)) {
                    heartRateStatLabel("평균", averageHeartRateBPM)
                    if let minHeartRateBPM {
                        heartRateStatLabel("최저", minHeartRateBPM)
                    }
                    if let maxHeartRateBPM {
                        heartRateStatLabel("최고", maxHeartRateBPM, showsUnit: true)
                    }
                }
                .fixedSize()
            }
        } else if isScrubbingChart,
                  let distance = scrubbedDistanceKilometers,
                  let altitude = elevation(at: distance) {
            Text("\(Int(altitude.rounded())) m")
                .font(.system(
                    size: HikingRecordCardLayout.cardSecondarySize.recordScaled(layoutScale),
                    weight: .medium
                ))
                .foregroundStyle(.orange)
                .monospacedDigit()
        } else {
            Text("최고 \(maxElevationMeters) m")
                .font(.system(
                    size: HikingRecordCardLayout.cardProfileMetricValueSize.recordScaled(layoutScale),
                    weight: .medium
                ))
                .foregroundStyle(.orange)
                .monospacedDigit()
        }
    }

    private var dataMaxDistanceKilometers: Double {
        max(
            chartPoints.last?.distanceKilometers ?? 0,
            heartRateChartPoints.last?.distanceKilometers ?? 0
        )
    }

    private var xAxisSpec: ProfileDistanceAxisSpec {
        ProfileDistanceAxisSpec.make(maxKilometers: dataMaxDistanceKilometers)
    }

    private var chartXDomain: ClosedRange<Double> {
        xAxisSpec.domain
    }

    private var elevationYDomain: ClosedRange<Double> {
        elevationAxisSpec.domain
    }

    private var heartRateYDomain: ClosedRange<Double> {
        heartRateAxisSpec.domain
    }

    private var elevationYTickValues: [Int] {
        elevationAxisSpec.ticks
    }

    private var heartRateYTickValues: [Int] {
        heartRateAxisSpec.ticks
    }

    private var xTickValues: [Double] {
        xAxisSpec.ticks
    }

    private var scrubLineColor: Color {
        showsHeartRateOverlay && activeMetric == .heartRate ? .red : .orange
    }

    private func setActiveMetric(_ metric: ElevationProfileActiveMetric) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            activeMetric = metric
            isScrubbingChart = false
            scrubbedDistanceKilometers = nil
            lastScrubHapticSampleIndex = nil
        }
    }

    private func distanceKilometers(forPlotX x: CGFloat, plotWidth: CGFloat) -> Double {
        guard plotWidth > 0 else { return chartXDomain.lowerBound }
        let ratio = min(max(Double(x / plotWidth), 0), 1)
        let domain = chartXDomain
        return domain.lowerBound + (domain.upperBound - domain.lowerBound) * ratio
    }

    private func elevation(at distanceKilometers: Double) -> Double? {
        interpolatedValue(
            at: distanceKilometers,
            from: chartPoints.map { ($0.distanceKilometers, $0.altitude) }
        )
    }

    private func heartRate(at distanceKilometers: Double) -> Double? {
        interpolatedValue(
            at: distanceKilometers,
            from: heartRateChartPoints.map { ($0.distanceKilometers, $0.bpm) }
        )
    }

    private func interpolatedValue(
        at distanceKilometers: Double,
        from samples: [(Double, Double)],
        maxGapKilometers: Double? = nil
    ) -> Double? {
        guard !samples.isEmpty else { return nil }

        let sorted = samples.sorted { $0.0 < $1.0 }
        if distanceKilometers <= sorted[0].0 { return sorted[0].1 }
        if distanceKilometers >= sorted[sorted.count - 1].0 { return sorted[sorted.count - 1].1 }

        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let next = sorted[index]
            guard distanceKilometers <= next.0 else { continue }

            let gap = next.0 - previous.0
            if let maxGapKilometers, gap > maxGapKilometers {
                let distanceToPrevious = distanceKilometers - previous.0
                let distanceToNext = next.0 - distanceKilometers
                return distanceToPrevious <= distanceToNext ? previous.1 : next.1
            }

            guard gap > 0 else { return next.1 }
            let ratio = (distanceKilometers - previous.0) / gap
            return previous.1 + (next.1 - previous.1) * ratio
        }

        return sorted.last?.1
    }

    private func chartScrubGesture(plotWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                isScrubbingChart = true
                updateChartScrub(atPlotX: value.location.x, plotWidth: plotWidth)
            }
            .onEnded { _ in
                isScrubbingChart = false
                scrubbedDistanceKilometers = nil
                lastScrubHapticSampleIndex = nil
            }
    }

    private func updateChartScrub(atPlotX x: CGFloat, plotWidth: CGFloat) {
        let distance = distanceKilometers(forPlotX: x, plotWidth: plotWidth)
        scrubbedDistanceKilometers = distance

        let sampleDistances = activeSampleDistances
        guard !sampleDistances.isEmpty else { return }

        let index = sampleIndex(at: distance, in: sampleDistances)
        if let lastIndex = lastScrubHapticSampleIndex, index != lastIndex {
            emitChartScrubSelections(from: lastIndex, to: index)
        }
        lastScrubHapticSampleIndex = index
    }

    private func plotX(forDistance distance: Double, plotWidth: CGFloat) -> CGFloat {
        let domain = chartXDomain
        let span = domain.upperBound - domain.lowerBound
        guard span > 0, plotWidth > 0 else { return 0 }
        let ratio = min(max((distance - domain.lowerBound) / span, 0), 1)
        return CGFloat(ratio) * plotWidth
    }

    private func sampleIndex(at distanceKilometers: Double, in samples: [Double]) -> Int {
        var index = 0
        for candidateIndex in samples.indices where samples[candidateIndex] <= distanceKilometers {
            index = candidateIndex
        }
        return index
    }

    private func emitChartScrubSelections(from startIndex: Int, to endIndex: Int) {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        if endIndex > startIndex {
            for _ in (startIndex + 1)...endIndex {
                generator.selectionChanged()
            }
        } else {
            for _ in endIndex..<startIndex {
                generator.selectionChanged()
            }
        }
    }

    private var activeSampleDistances: [Double] {
        if showsHeartRateOverlay, activeMetric == .heartRate {
            return heartRateChartPoints.map(\.distanceKilometers)
        }
        return chartPoints.map(\.distanceKilometers)
    }

    @ViewBuilder
    private var profileChart: some View {
        VStack(spacing: plotXAxisGap) {
            HStack(alignment: .top, spacing: 0) {
                elevationAxisLegendColumn
                    .frame(width: sharedYAxisColumnWidth, height: plotAreaHeight, alignment: .top)

                Color.clear.frame(width: yAxisGraphGap)

                profilePlotStack
                    .frame(maxWidth: .infinity)
                    .frame(height: plotAreaHeight)
                    .clipped()

                Color.clear.frame(width: yAxisGraphGap)

                if showsHeartRateOverlay {
                    heartRateAxisLegendColumn
                        .frame(width: sharedYAxisColumnWidth, height: plotAreaHeight, alignment: .top)
                } else {
                    Color.clear.frame(width: sharedYAxisColumnWidth, height: plotAreaHeight)
                }
            }
            .frame(height: plotAreaHeight)

            xAxisLegendRow
                .frame(height: xAxisRowHeight, alignment: .top)
        }
        .animation(nil, value: activeMetric)
    }

    private var elevationAxisLegendColumn: some View {
        axisLegendColumn(
            values: elevationYTickValues,
            domain: elevationYDomain,
            activeColor: .orange,
            isActive: !showsHeartRateOverlay || activeMetric == .elevation,
            graphEdge: .graphOnTrailing
        )
    }

    private var heartRateAxisLegendColumn: some View {
        axisLegendColumn(
            values: heartRateYTickValues,
            domain: heartRateYDomain,
            activeColor: .red,
            isActive: activeMetric == .heartRate,
            graphEdge: .graphOnLeading
        )
    }

    private enum YAxisGraphAdjacentEdge {
        /// 그래프가 열 오른쪽(좌측 Y축).
        case graphOnTrailing
        /// 그래프가 열 왼쪽(우측 Y축).
        case graphOnLeading
    }

    /// 눈금을 값 비례 위치에 배치(0=맨 아래, 최고=맨 위). 차트와 동일 인셋을 써 그래프가 눈금에 맞습니다.
    private func axisLegendColumn(
        values: [Int],
        domain: ClosedRange<Double>,
        activeColor: Color,
        isActive: Bool,
        graphEdge: YAxisGraphAdjacentEdge
    ) -> some View {
        let inset = plotEdgeInset
        let span = max(domain.upperBound - domain.lowerBound, 1)
        let bandWidth = yAxisTickLabelBandWidth
        let bandPlacement: Alignment = graphEdge == .graphOnTrailing ? .trailing : .leading
        return GeometryReader { geometry in
            let usableHeight = max(geometry.size.height - inset * 2, 0)
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                let fraction = (Double(value) - domain.lowerBound) / span
                Text(yAxisTickLabel(value))
                    .font(.system(size: Self.axisTickFontSize.recordScaled(layoutScale), weight: .medium))
                    .foregroundStyle(isActive ? activeColor : Color.secondary.opacity(0.55))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: bandWidth, alignment: .trailing)
                    .frame(maxWidth: geometry.size.width, alignment: bandPlacement)
                    .position(
                        x: geometry.size.width / 2,
                        y: inset + (1 - CGFloat(fraction)) * usableHeight
                    )
            }
        }
    }

    /// Y축 눈금 — 천 단위 구분 없이 표시해 좁은 열에서 줄바꿈을 방지합니다.
    private func yAxisTickLabel(_ value: Int) -> String {
        "\(value)"
    }

    private var xAxisLegendRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: sharedYAxisColumnWidth)
            Color.clear.frame(width: yAxisGraphGap)

            GeometryReader { geometry in
                let ticks = xTickValues
                let plotWidth = geometry.size.width
                ZStack(alignment: .topLeading) {
                    ForEach(Array(ticks.enumerated()), id: \.offset) { index, tick in
                        Text(xTickLabel(tick))
                            .font(.system(size: Self.axisTickFontSize.recordScaled(layoutScale)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .fixedSize()
                            .position(
                                x: xTickLabelX(
                                    tick: tick,
                                    index: index,
                                    tickCount: ticks.count,
                                    plotWidth: plotWidth
                                ),
                                y: geometry.size.height / 2
                            )
                    }
                }
            }
            .frame(height: xAxisRowHeight)

            Color.clear.frame(width: yAxisGraphGap)
            Color.clear.frame(width: sharedYAxisColumnWidth)
        }
    }

    private func xTickLabelX(tick: Double, index: Int, tickCount: Int, plotWidth: CGFloat) -> CGFloat {
        let domainMax = chartXDomain.upperBound
        guard domainMax > 0, plotWidth > 0 else { return 0 }

        let fraction = tick / domainMax
        let proportionalX = CGFloat(fraction) * plotWidth
        let edgeInset = max(4, 5.recordScaled(layoutScale))

        if index == 0 { return edgeInset }
        if index == tickCount - 1 { return plotWidth - edgeInset }
        return proportionalX
    }

    private func xTickLabel(_ tick: Double) -> String {
        let rounded = (tick * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.001 {
            return "\(Int(rounded.rounded()))"
        }
        return String(format: "%.1f", rounded)
    }

    private var profilePlotStack: some View {
        let elevationActive = !showsHeartRateOverlay || activeMetric == .elevation
        let heartRateActive = showsHeartRateOverlay && activeMetric == .heartRate

        return ZStack {
            elevationPlotChart(isActive: elevationActive)

            if showsHeartRateOverlay {
                heartRatePlotChart(isActive: heartRateActive)
            }
        }
        .overlay {
            GeometryReader { geometry in
                ZStack {
                    if isScrubbingChart, let distance = scrubbedDistanceKilometers {
                        let x = plotX(forDistance: distance, plotWidth: geometry.size.width)
                        Rectangle()
                            .fill(scrubLineColor.opacity(0.9))
                            .frame(
                                width: max(1, CGFloat(1.5).recordScaled(layoutScale)),
                                height: geometry.size.height
                            )
                            .position(x: x, y: geometry.size.height / 2)
                            .allowsHitTesting(false)
                    }

                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(chartScrubGesture(plotWidth: geometry.size.width))
                }
            }
        }
    }

    private func elevationPlotChart(isActive: Bool) -> some View {
        Chart {
            if isScrubbingChart, isActive, let scrubDistance = scrubbedDistanceKilometers {
                let split = splitElevationPoints(at: scrubDistance)
                elevationMarks(
                    for: split.leading,
                    series: "고도-이전",
                    lineStyle: AnyShapeStyle(Color.orange.gradient),
                    areaStyle: Color.orange.opacity(0.15)
                )
                elevationMarks(
                    for: split.trailing,
                    series: "고도-이후",
                    lineStyle: AnyShapeStyle(Self.inactiveLineColor),
                    areaStyle: Self.inactiveAreaColor
                )
            } else {
                elevationMarks(
                    for: chartPoints,
                    series: "고도",
                    lineStyle: isActive ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(Self.inactiveLineColor),
                    areaStyle: isActive ? Color.orange.opacity(0.15) : Self.inactiveAreaColor
                )
            }
        }
        .profilePlotChartStyle(
            xDomain: chartXDomain,
            yDomain: elevationYDomain,
            yEdgeInset: plotEdgeInset
        )
    }

    @ChartContentBuilder
    private func elevationMarks(
        for points: [ElevationProfileChartPoint],
        series: String,
        lineStyle: AnyShapeStyle,
        areaStyle: Color
    ) -> some ChartContent {
        ForEach(points) { point in
            LineMark(
                x: .value("거리", point.distanceKilometers),
                y: .value("고도", point.altitude),
                series: .value("측정", series)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(lineStyle)

            AreaMark(
                x: .value("거리", point.distanceKilometers),
                yStart: .value("기준", elevationYDomain.lowerBound),
                yEnd: .value("고도", point.altitude),
                series: .value("측정", series)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(areaStyle)
        }
    }

    private func splitElevationPoints(
        at scrubDistance: Double
    ) -> (leading: [ElevationProfileChartPoint], trailing: [ElevationProfileChartPoint]) {
        guard let altitude = elevation(at: scrubDistance) else {
            return (chartPoints, [])
        }

        let leadingAnchor = ElevationProfileChartPoint(
            id: ProfileChartScrub.leadingAnchorPointID,
            distanceKilometers: scrubDistance,
            altitude: altitude
        )
        let trailingAnchor = ElevationProfileChartPoint(
            id: ProfileChartScrub.trailingAnchorPointID,
            distanceKilometers: scrubDistance,
            altitude: altitude
        )

        var leading = chartPoints.filter { $0.distanceKilometers <= scrubDistance }
        if leading.last?.distanceKilometers != scrubDistance {
            leading.append(leadingAnchor)
        }

        var trailing = chartPoints.filter { $0.distanceKilometers >= scrubDistance }
        if trailing.first?.distanceKilometers != scrubDistance {
            trailing.insert(trailingAnchor, at: 0)
        }
        if trailing.count <= 1 {
            trailing = []
        }

        return (leading, trailing)
    }

    private func heartRatePlotChart(isActive: Bool) -> some View {
        Chart {
            if isScrubbingChart, isActive, let scrubDistance = scrubbedDistanceKilometers {
                let split = splitHeartRatePoints(at: scrubDistance)
                heartRateMarks(
                    for: split.leading,
                    series: "심박-이전",
                    lineStyle: AnyShapeStyle(Color.red.gradient),
                    areaStyle: Color.red.opacity(0.14)
                )
                heartRateMarks(
                    for: split.trailing,
                    series: "심박-이후",
                    lineStyle: AnyShapeStyle(Self.inactiveLineColor),
                    areaStyle: Self.inactiveAreaColor
                )
            } else {
                heartRateMarks(
                    for: heartRateChartPoints,
                    series: "심박",
                    lineStyle: isActive ? AnyShapeStyle(Color.red.gradient) : AnyShapeStyle(Self.inactiveLineColor),
                    areaStyle: isActive ? Color.red.opacity(0.14) : Self.inactiveAreaColor
                )
            }
        }
        .profilePlotChartStyle(
            xDomain: chartXDomain,
            yDomain: heartRateYDomain,
            yEdgeInset: plotEdgeInset
        )
    }

    @ChartContentBuilder
    private func heartRateMarks(
        for points: [HeartRateProfileChartPoint],
        series: String,
        lineStyle: AnyShapeStyle,
        areaStyle: Color
    ) -> some ChartContent {
        ForEach(points) { point in
            LineMark(
                x: .value("거리", point.distanceKilometers),
                y: .value("심박", point.bpm),
                series: .value("측정", series)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(lineStyle)

            AreaMark(
                x: .value("거리", point.distanceKilometers),
                yStart: .value("기준", heartRateYDomain.lowerBound),
                yEnd: .value("심박", point.bpm),
                series: .value("측정", series)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(areaStyle)
        }
    }

    private func splitHeartRatePoints(
        at scrubDistance: Double
    ) -> (leading: [HeartRateProfileChartPoint], trailing: [HeartRateProfileChartPoint]) {
        guard let bpm = heartRate(at: scrubDistance) else {
            return (heartRateChartPoints, [])
        }

        let leadingAnchor = HeartRateProfileChartPoint(
            id: ProfileChartScrub.leadingAnchorPointID,
            distanceKilometers: scrubDistance,
            bpm: bpm
        )
        let trailingAnchor = HeartRateProfileChartPoint(
            id: ProfileChartScrub.trailingAnchorPointID,
            distanceKilometers: scrubDistance,
            bpm: bpm
        )

        var leading = heartRateChartPoints.filter { $0.distanceKilometers <= scrubDistance }
        if leading.last?.distanceKilometers != scrubDistance {
            leading.append(leadingAnchor)
        }

        var trailing = heartRateChartPoints.filter { $0.distanceKilometers >= scrubDistance }
        if trailing.first?.distanceKilometers != scrubDistance {
            trailing.insert(trailingAnchor, at: 0)
        }
        if trailing.count <= 1 {
            trailing = []
        }

        return (leading, trailing)
    }
}

private enum ProfileChartScrub {
    static let leadingAnchorPointID = UUID()
    static let trailingAnchorPointID = UUID()
}

private extension View {
    func profilePlotChartStyle(
        xDomain: ClosedRange<Double>,
        yDomain: ClosedRange<Double>,
        yEdgeInset: CGFloat
    ) -> some View {
        chartXScale(domain: xDomain)
            .chartYScale(
                domain: yDomain,
                range: .plotDimension(startPadding: yEdgeInset, endPadding: yEdgeInset)
            )
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartPlotStyle { plot in
                plot.background(.clear)
            }
    }
}

// MARK: - 요약 섹션

struct HikingRecordSummarySection: View {
    @Environment(\.recordCardLayoutScale) private var layoutScale

    let record: SavedHikingSession
    var horizontalPadding: CGFloat = 0

    private var summaryFooterText: String {
        let points = "GPS \(record.session.points.count)개 포인트"
        let photoCount = record.session.photos.count
        if photoCount > 0 {
            return "\(points) · 사진 \(photoCount)장"
        }
        return points
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HikingRecordCardLayout.cardGridSpacing.recordScaled(layoutScale)) {
            RecordScheduleCard(record: record, heroStyle: true)

            HStack(alignment: .top, spacing: HikingRecordCardLayout.cardGridSpacing.recordScaled(layoutScale)) {
                RecordStatCard(
                    title: "거리",
                    value: record.distanceValueText,
                    unit: record.distanceUnitText,
                    icon: "figure.hiking",
                    tint: .green,
                    newsStyle: true
                )
                RecordStatCard(
                    title: "상승",
                    value: record.elevationValueText,
                    unit: record.elevationUnitText,
                    icon: "mountain.2.fill",
                    tint: .orange,
                    newsStyle: true
                )
                RecordStatCard(
                    title: "평균속도",
                    value: record.averageSpeedValueText,
                    unit: record.averageSpeedUnitText,
                    icon: "speedometer",
                    tint: .purple,
                    newsStyle: true
                )
            }

            HStack(alignment: .top, spacing: HikingRecordCardLayout.cardGridSpacing.recordScaled(layoutScale)) {
                RecordStatCard(
                    title: "걸음수",
                    value: record.stepCountValueText,
                    unit: record.stepCountUnitText,
                    icon: "shoeprints.fill",
                    tint: .pink,
                    newsStyle: true
                )
                RecordStatCard(
                    title: "칼로리",
                    value: record.caloriesValueText,
                    unit: record.caloriesUnitText,
                    icon: "flame.fill",
                    tint: .red,
                    newsStyle: true
                )
            }

            HikingElevationProfileCard(
                points: record.session.points,
                heartRateSamples: record.session.heartRateSamples,
                persistedElevationProfile: record.session.elevationProfile,
                persistedHeartRateProfile: record.session.heartRateProfile
            )

            Text(summaryFooterText)
                .font(.system(size: 11.recordScaled(layoutScale), weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, horizontalPadding)
    }
}

struct RecordScheduleCard: View {
    @Environment(\.recordCardLayoutScale) private var layoutScale

    let record: SavedHikingSession
    var heroStyle: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: HikingRecordCardLayout.cardGridSpacing.recordScaled(layoutScale)) {
            ScheduleTile(
                label: "시작",
                parts: record.startedScheduleParts,
                icon: "play.circle.fill",
                tint: .green,
                heroStyle: heroStyle
            )
            ScheduleTile(
                label: "종료",
                parts: record.endedScheduleParts,
                icon: "flag.checkered",
                tint: Color(.systemGray),
                heroStyle: heroStyle
            )
            if heroStyle {
                RecordStatCard(
                    title: "시간",
                    value: record.formattedDurationCompact,
                    unit: "",
                    icon: "clock.fill",
                    tint: .blue,
                    newsStyle: true
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScheduleTile: View {
    let label: String
    let parts: ScheduleDateParts?
    let icon: String
    let tint: Color
    var heroStyle: Bool = false

    var body: some View {
        Group {
            if heroStyle, let parts {
                RecordScheduleMetricCard(
                    label: label,
                    parts: parts,
                    icon: icon,
                    tint: tint
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text(parts.map { "\($0.dateText) \($0.timeText)" } ?? "—")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RecordStatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let tint: Color
    var newsStyle: Bool = false

    var body: some View {
        Group {
            if newsStyle {
                RecordSummaryMetricCard(
                    label: title,
                    primaryText: value,
                    primarySuffix: unit.isEmpty ? nil : unit,
                    icon: icon,
                    tint: tint
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: icon)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)

                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(value)
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                }
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#endif
