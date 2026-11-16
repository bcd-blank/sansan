//
//  HikingRecordSummaryShareComposer.swift
//  sansan
//
//  Share-summary A안: gray map + floating white card. Layout from share.summary.*
//  tokens; km labels via shared RouteKilometerMarkerMetrics.
//

#if os(iOS)

import SwiftUI
import UIKit

@MainActor
enum HikingRecordSummaryShareComposer {
    static func render(
        record: SavedHikingSession,
        mapOptions: HikingShareMapExportOptions
    ) async -> UIImage? {
        let width = HikingRecordShareDeviceMetrics.fullScreenBounds.width
        let scale = HikingRecordShareDeviceMetrics.nativeScale
        let canvas = ShareSummaryTokens.canvasSize(widthPoints: width, pixelScale: scale)
        let s = ShareSummaryTokens.ptScale(for: canvas.width)
        let memoLines = ShareSummaryTokens.memoLineCount(record.memo, canvasWidth: canvas.width)
        var captureOptions = mapOptions
        captureOptions.showsPinnedThumbnails = false
        guard let map = await HikingRouteSnapshotGenerator.fittedMapImage(
            record: record,
            canvasSize: canvas,
            pixelScale: scale,
            mapOptions: captureOptions,
            insetTop: ShareSummaryTokens.mapTopInset(memoLineCount: memoLines) * s,
            insetBottom: ShareSummaryTokens.mapBottomInset * s,
            insetLeft: ShareSummaryTokens.mapSideInset * s,
            insetRight: ShareSummaryTokens.mapSideInset * s,
            routeFillFraction: 1,
            appearance: .shareSummary,
            fadeSolidEndY: ShareSummaryTokens.fadeSolidEnd(memoLineCount: memoLines) * s
        ) else { return nil }

        let page = SummaryMapSharePage(
            record: record,
            mapImage: map,
            memoLineCount: memoLines
        )
        .frame(width: canvas.width, height: canvas.height)
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: page)
        renderer.proposedSize = ProposedViewSize(width: canvas.width, height: canvas.height)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

// MARK: - Page

private struct SummaryMapSharePage: View {
    let record: SavedHikingSession
    let mapImage: UIImage
    let memoLineCount: Int

    private var s: CGFloat { ShareSummaryTokens.ptScale(for: mapImage.size.width) }

    private var showsWeather: Bool {
        HikingShareExportPreferences.mapOptions.showsWeatherLabel && record.weather != nil
    }

    var body: some View {
        ZStack {
            Image(uiImage: mapImage)
                .resizable()
                .frame(width: mapImage.size.width, height: mapImage.size.height)

            // Fade is baked under the route in the snapshot (finding 2). Header sits above.

            headerBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            mapsAttribution
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            // Sharp white hinter so MapKit legal marks cannot peek past the card corner (finding 3).
            Color.white
                .frame(height: ShareSummaryTokens.cardHeight * s)
                .padding(.horizontal, ShareSummaryTokens.cardInset * s)
                .padding(.bottom, ShareSummaryTokens.cardInset * s)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

            SummaryInfoCard(record: record, scale: s)
                .padding(.horizontal, ShareSummaryTokens.cardInset * s)
                .padding(.bottom, ShareSummaryTokens.cardInset * s)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: mapImage.size.width, height: mapImage.size.height)
        .clipped()
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16 * s) {
                summaryLogo
                Spacer(minLength: 16 * s)
                if showsWeather, let weather = record.weather {
                    ShareSummaryWeatherCard(
                        weather: weather,
                        scale: s,
                        maxWidth: mapImage.size.width * ShareSummaryTokens.weatherMaxWidthFraction
                    )
                }
            }
            .frame(height: ShareSummaryTokens.headerRow1Height * s, alignment: .center)

            Text(record.exportCardTitle)
                .font(.system(size: ShareSummaryTokens.headerTitleSize * s, weight: .bold))
                .tracking(-0.2 * s)
                .foregroundStyle(Color(ShareSummaryTokens.inkUIColor))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, ShareSummaryTokens.headerTitleGap * s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: ShareSummaryTokens.headerTitleLineHeight * s, alignment: .center)

            if let memo = record.memo?.trimmingCharacters(in: .whitespacesAndNewlines), !memo.isEmpty {
                ShareSummaryMemoText(text: memo, scale: s, lineCount: max(memoLineCount, 1))
                    .padding(.top, ShareSummaryTokens.memoGapFromTitle * s)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, ShareSummaryTokens.headerTop * s)
        .padding(.horizontal, ShareSummaryTokens.headerInset * s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryLogo: some View {
        let height = ShareSummaryTokens.headerLogoHeight * s
        return Image("SansanLogoSymbol")
            .resizable()
            .aspectRatio(RouteBrandLogoMetrics.artworkAspect, contentMode: .fit)
            .frame(height: height)
    }

    /// Apple logo + 「지도」 only — snapshot legal mark is covered by the card hinter (S10).
    private var mapsAttribution: some View {
        HStack(alignment: .center, spacing: 2 * s) {
            Image(systemName: "apple.logo")
                .font(.system(size: ShareSummaryTokens.attributionHeight * s, weight: .regular))
            Text("지도")
                .font(.system(size: ShareSummaryTokens.attributionHeight * s, weight: .regular))
        }
        .foregroundStyle(Color(ShareSummaryTokens.mapTextUIColor))
        .frame(height: ShareSummaryTokens.attributionHeight * s)
        .padding(.leading, ShareSummaryTokens.attributionX * s)
        .padding(
            .bottom,
            (ShareSummaryTokens.cardInset + ShareSummaryTokens.cardHeight + ShareSummaryTokens.attributionGapAboveCard) * s
        )
    }
}

// MARK: - Memo (exact line height 17)

private struct ShareSummaryMemoText: View {
    let text: String
    let scale: CGFloat
    let lineCount: Int

    var body: some View {
        let height = CGFloat(min(ShareSummaryTokens.memoMaxLines, lineCount)) * ShareSummaryTokens.memoLineHeight * scale
        Text(attributed)
            .lineLimit(ShareSummaryTokens.memoMaxLines)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        let font = UIFont.systemFont(ofSize: ShareSummaryTokens.memoFontSize * scale, weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = ShareSummaryTokens.memoLineHeight * scale
        paragraph.maximumLineHeight = ShareSummaryTokens.memoLineHeight * scale
        paragraph.lineBreakMode = .byTruncatingTail
        let ns = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: ShareSummaryTokens.mapTextUIColor,
                .kern: ShareSummaryTokens.memoTracking * scale,
                .paragraphStyle: paragraph
            ]
        )
        return AttributedString(ns)
    }
}

// MARK: - Weather

private struct ShareSummaryWeatherCard: View {
    let weather: HikingRouteWeatherSnapshot
    let scale: CGFloat
    let maxWidth: CGFloat

    private var hours: [HikingWeatherHourPoint] {
        let minScale = ShareSummaryTokens.weatherMinScale * scale
        let capacity = columnCapacity(at: minScale)
        return HikingRouteWeatherSnapshot.timelineFitting(
            weather.timelineHours,
            maximumCount: min(ShareSummaryTokens.weatherMaxColumns, capacity)
        )
    }

    /// Fit card into maxWidth; floor at weatherMinScale × layout scale.
    private var displayScale: CGFloat {
        let naturalDesign = chipWidth(hours: hours, scale: 1)
        guard naturalDesign > 0 else { return scale }
        let fitted = maxWidth / naturalDesign
        return min(scale, max(fitted, ShareSummaryTokens.weatherMinScale * scale))
    }

    var body: some View {
        let s = displayScale
        HStack(alignment: .top, spacing: ShareSummaryTokens.weatherColumnGap * s) {
            ForEach(hours) { hour in
                VStack(spacing: ShareSummaryTokens.weatherIconTempGap * s) {
                    Image(systemName: HikingRouteWeatherSnapshot.symbolName(for: hour.wmoCode))
                        .font(.system(size: ShareSummaryTokens.weatherIconSize * s, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            WeatherIconPalette.primary(for: hour.wmoCode),
                            WeatherIconPalette.secondary(for: hour.wmoCode)
                        )
                        .frame(
                            width: ShareSummaryTokens.weatherColumnWidth * s,
                            height: ShareSummaryTokens.weatherIconSize * s
                        )
                    Text(hour.formattedTemperature)
                        .font(.system(size: ShareSummaryTokens.weatherTempSize * s, weight: .semibold))
                        .foregroundStyle(Color(ShareSummaryTokens.inkUIColor))
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: ShareSummaryTokens.weatherColumnWidth * s)
                }
            }
        }
        .padding(.horizontal, ShareSummaryTokens.weatherPaddingH * s)
        .padding(.vertical, ShareSummaryTokens.weatherPaddingV * s)
        .frame(height: ShareSummaryTokens.weatherHeight * s)
        .background(Color.white, in: RoundedRectangle(cornerRadius: ShareSummaryTokens.weatherRadius * s, style: .continuous))
        .shadow(color: Color(ShareSummaryTokens.inkUIColor).opacity(0.08), radius: 0.5 * s, y: 0)
        .shadow(color: Color(ShareSummaryTokens.inkUIColor).opacity(0.08), radius: 4 * s, y: 2 * s)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func columnCapacity(at scale: CGFloat) -> Int {
        guard scale > 0, maxWidth > 0 else { return 1 }
        let column = ShareSummaryTokens.weatherColumnWidth * scale
        let gap = ShareSummaryTokens.weatherColumnGap * scale
        let pad = ShareSummaryTokens.weatherPaddingH * 2 * scale
        let count = Int(((maxWidth - pad + gap) / (column + gap)).rounded(.down))
        return max(1, min(ShareSummaryTokens.weatherMaxColumns, count))
    }

    private func chipWidth(hours: [HikingWeatherHourPoint], scale: CGFloat) -> CGFloat {
        guard !hours.isEmpty else { return 0 }
        let n = CGFloat(hours.count)
        return ShareSummaryTokens.weatherPaddingH * 2 * scale
            + ShareSummaryTokens.weatherColumnWidth * n * scale
            + ShareSummaryTokens.weatherColumnGap * max(n - 1, 0) * scale
    }
}

// MARK: - Info card

private struct SummaryInfoCard: View {
    let record: SavedHikingSession
    let scale: CGFloat

    private var elevationSamples: [HikingElevationChartSample] {
        if let stored = record.session.elevationProfile, stored.count >= 2 {
            return stored
        }
        return HikingSessionMetrics.elevationProfileSamples(from: record.session.points).map {
            HikingElevationChartSample(id: $0.id, distanceMeters: $0.distanceMeters, altitude: $0.altitude)
        }
    }

    private var heartSamples: [HikingHeartRateChartSample] {
        if let stored = record.session.heartRateProfile, stored.count >= 2 {
            return stored
        }
        return HikingSessionMetrics.heartRateProfileSamples(
            from: record.session.points,
            heartRateSamples: record.session.heartRateSamples
        ).map {
            HikingHeartRateChartSample(id: $0.id, distanceMeters: $0.distanceMeters, bpm: $0.bpm)
        }
    }

    /// Peak elevation from profile samples — current app meaning of 「고도 N m」.
    private var maxElevation: Int {
        Int((elevationSamples.map(\.altitude).max() ?? 0).rounded())
    }

    private var heartStats: (average: Int, minimum: Int, maximum: Int)? {
        let values = heartSamples.map(\.bpm)
        guard let minValue = values.min(), let maxValue = values.max(), !values.isEmpty else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        return (Int(average.rounded()), Int(minValue.rounded()), Int(maxValue.rounded()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ShareSummaryTokens.cardBlockGap * scale) {
            heroRow
                .padding(.horizontal, ShareSummaryTokens.cardPaddingH * scale)

            divider

            metricsRow
                .padding(.horizontal, ShareSummaryTokens.cardPaddingH * scale)
            metaRow
                .padding(.horizontal, ShareSummaryTokens.cardPaddingH * scale)
            chartBlock
                .padding(.horizontal, ShareSummaryTokens.cardPaddingH * scale)
        }
        .padding(.top, ShareSummaryTokens.cardPaddingTop * scale)
        .padding(.bottom, ShareSummaryTokens.cardPaddingBottom * scale)
        .frame(height: ShareSummaryTokens.cardHeight * scale, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.white,
            in: RoundedRectangle(cornerRadius: ShareSummaryTokens.cardRadius * scale, style: .continuous)
        )
        .shadow(color: Color(ShareSummaryTokens.inkUIColor).opacity(0.10), radius: 16 * scale, y: 12 * scale)
        .shadow(color: Color(ShareSummaryTokens.inkUIColor).opacity(0.06), radius: 1.5 * scale, y: 1 * scale)
    }

    private var heroRow: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                Text("거리")
                    .font(.system(size: ShareSummaryTokens.labelSize * scale, weight: .medium))
                    .foregroundStyle(Color(ShareSummaryTokens.ink2UIColor))
                    .frame(height: ShareSummaryTokens.labelLineHeight * scale, alignment: .center)
                HStack(alignment: .firstTextBaseline, spacing: ShareSummaryTokens.heroUnitGap * scale) {
                    Text(record.distanceValueText)
                        .font(.system(size: ShareSummaryTokens.heroSize * scale, weight: .light))
                        .tracking(-1.4 * scale)
                        .monospacedDigit()
                        .foregroundStyle(Color(ShareSummaryTokens.inkUIColor))
                    Text(record.distanceUnitText)
                        .font(.system(size: ShareSummaryTokens.heroUnitSize * scale, weight: .regular))
                        .foregroundStyle(Color(ShareSummaryTokens.ink2UIColor))
                }
                .frame(height: ShareSummaryTokens.heroLineHeight * scale, alignment: .center)
            }

            timeline
                .padding(.top, (ShareSummaryTokens.timelineFirstRowTop - ShareSummaryTokens.cardPaddingTop) * scale)
                .padding(.leading, (ShareSummaryTokens.timelineDotX - ShareSummaryTokens.cardInset - ShareSummaryTokens.cardPaddingH) * scale)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeline: some View {
        let start = timeLabel(record.startedScheduleParts)
        let end = timeLabel(record.endedScheduleParts)
        let dot = ShareSummaryTokens.timelineDot * scale
        let line = ShareSummaryTokens.timelineLine * scale
        let row = ShareSummaryTokens.timeLineHeight * scale
        let gap = ShareSummaryTokens.timelineRowGap * scale
        return VStack(alignment: .leading, spacing: 0) {
            timelineRow(dot: dot, text: start, rowHeight: row, fill: Color(ShareSummaryTokens.accentUIColor))
            Color.clear.frame(height: gap)
            HStack(spacing: ShareSummaryTokens.timelineTimeGap * scale) {
                Rectangle()
                    .fill(Color(ShareSummaryTokens.trackUIColor))
                    .frame(width: max(1 * scale, 1), height: line)
                    .frame(width: dot, alignment: .center)
                Spacer(minLength: 0)
            }
            Color.clear.frame(height: gap)
            timelineRow(dot: dot, text: end, rowHeight: row, fill: Color(ShareSummaryTokens.inkUIColor))
        }
    }

    private func timelineRow(dot: CGFloat, text: String, rowHeight: CGFloat, fill: Color) -> some View {
        HStack(alignment: .center, spacing: ShareSummaryTokens.timelineTimeGap * scale) {
            Circle()
                .fill(fill)
                .frame(width: dot, height: dot)
            Text(text)
                .font(.system(size: ShareSummaryTokens.timeSize * scale, weight: .regular))
                .foregroundStyle(Color(ShareSummaryTokens.inkUIColor))
                .monospacedDigit()
                .lineLimit(1)
                .frame(height: rowHeight, alignment: .center)
        }
        .frame(height: rowHeight, alignment: .center)
    }

    private var metricsRow: some View {
        HStack(alignment: .top, spacing: ShareSummaryTokens.cardColumnGap * scale) {
            metricColumn(label: "시간") {
                durationMetric(record.formattedDurationCompact)
            }
            metricColumn(label: "상승") {
                metricValue(record.elevationValueText, unit: "m")
            }
            metricColumn(label: "평균속도") {
                metricValue(record.averageSpeedValueText, unit: record.averageSpeedUnitText)
            }
        }
    }

    private var metaRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: ShareSummaryTokens.cardColumnGap * scale) {
            metaItem(value: record.stepCountValueText, unit: "걸음")
                .frame(width: ShareSummaryTokens.cardColumnWidth * scale, alignment: .leading)
            metaItem(value: record.caloriesValueText, unit: "kcal")
                .frame(width: ShareSummaryTokens.cardColumnWidth * scale, alignment: .leading)
            metaItem(value: "\(maxElevation)", unit: "m", label: "고도")
                .frame(width: ShareSummaryTokens.cardColumnWidth * scale, alignment: .leading)
        }
    }

    private var chartBlock: some View {
        VStack(alignment: .leading, spacing: ShareSummaryTokens.graphGapAbove * scale) {
            legendRow
            SummaryChartCanvas(elevation: elevationSamples, heartRate: heartSamples, scale: scale)
                .frame(height: ShareSummaryTokens.graphHeight * scale)
        }
    }

    private var legendRow: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1 * scale, style: .continuous)
                .fill(Color(ShareSummaryTokens.accentUIColor))
                .frame(
                    width: ShareSummaryTokens.graphLegendSwatchWidth * scale,
                    height: ShareSummaryTokens.graphLegendElevHeight * scale
                )
            Text("고도")
                .font(.system(size: ShareSummaryTokens.legendSize * scale, weight: .regular))
                .foregroundStyle(Color(ShareSummaryTokens.ink2UIColor))
                .padding(.leading, ShareSummaryTokens.graphLegendGap * scale)

            if let heartStats {
                Color.clear.frame(width: ShareSummaryTokens.graphLegendBlockGap * scale)
                RoundedRectangle(cornerRadius: 0.5 * scale, style: .continuous)
                    .fill(Color(ShareSummaryTokens.hrUIColor))
                    .frame(
                        width: ShareSummaryTokens.graphLegendSwatchWidth * scale,
                        height: ShareSummaryTokens.graphLegendHRHeight * scale
                    )
                Text("심박")
                    .font(.system(size: ShareSummaryTokens.legendSize * scale, weight: .regular))
                    .foregroundStyle(Color(ShareSummaryTokens.ink2UIColor))
                    .padding(.leading, ShareSummaryTokens.graphLegendGap * scale)
                Text("\(heartStats.average)")
                    .font(.system(size: ShareSummaryTokens.legendSize * scale, weight: .medium))
                    .foregroundStyle(Color(ShareSummaryTokens.inkUIColor))
                    .monospacedDigit()
                    .padding(.leading, 4 * scale)
                Text("\(heartStats.minimum)–\(heartStats.maximum)")
                    .font(.system(size: ShareSummaryTokens.legendSize * scale, weight: .regular))
                    .foregroundStyle(Color(ShareSummaryTokens.ink2UIColor))
                    .monospacedDigit()
                    .padding(.leading, 4 * scale)
            }
            Spacer(minLength: 0)
        }
        .frame(height: ShareSummaryTokens.legendLineHeight * scale, alignment: .center)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(ShareSummaryTokens.hairlineUIColor))
            .frame(height: ShareSummaryTokens.hairlineWidth(scale: scale))
            .frame(maxWidth: .infinity)
    }

    private func metricColumn<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: ShareSummaryTokens.labelSize * scale, weight: .medium))
                .foregroundStyle(Color(ShareSummaryTokens.ink2UIColor))
                .frame(height: ShareSummaryTokens.labelLineHeight * scale, alignment: .center)
            content()
                .frame(height: ShareSummaryTokens.metricLineHeight * scale, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: ShareSummaryTokens.cardColumnWidth * scale, alignment: .leading)
    }

    private func metricValue(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ShareSummaryTokens.metricUnitGap * scale) {
            Text(value)
                .font(.system(size: ShareSummaryTokens.metricSize * scale, weight: .light))
                .tracking(-0.5 * scale)
                .monospacedDigit()
                .foregroundStyle(Color(ShareSummaryTokens.inkUIColor))
            Text(unit)
                .font(.system(size: ShareSummaryTokens.metricUnitSize * scale, weight: .regular))
                .foregroundStyle(Color(ShareSummaryTokens.ink2UIColor))
        }
        .lineLimit(1)
        .minimumScaleFactor(ShareSummaryTokens.metricMinScale)
    }

    private func durationMetric(_ compact: String) -> some View {
        let parts = durationParts(compact)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Color.clear.frame(
                        width: durationGap(before: parts[index - 1], current: part) * scale,
                        height: 1
                    )
                }
                Text(part.text)
                    .font(.system(
                        size: (part.isUnit ? ShareSummaryTokens.metricUnitSize : ShareSummaryTokens.metricSize) * scale,
                        weight: part.isUnit ? .regular : .light
                    ))
                    .tracking(part.isUnit ? 0 : -0.5 * scale)
                    .monospacedDigit()
                    .foregroundStyle(
                        part.isUnit
                            ? Color(ShareSummaryTokens.ink2UIColor)
                            : Color(ShareSummaryTokens.inkUIColor)
                    )
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(ShareSummaryTokens.metricMinScale)
    }

    private func durationGap(before: DurationPart, current: DurationPart) -> CGFloat {
        if before.isUnit && !current.isUnit {
            return ShareSummaryTokens.metricUnitTrailing
        }
        return ShareSummaryTokens.metricUnitGap
    }

    private func metaItem(value: String, unit: String, label: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: ShareSummaryTokens.metaUnitGap * scale) {
            if let label {
                Text(label)
                    .font(.system(size: ShareSummaryTokens.metaSize * scale, weight: .regular))
                    .foregroundStyle(Color(ShareSummaryTokens.ink2UIColor))
            }
            Text(value)
                .font(.system(size: ShareSummaryTokens.metaSize * scale, weight: .medium))
                .foregroundStyle(Color(ShareSummaryTokens.inkUIColor))
                .monospacedDigit()
            Text(unit)
                .font(.system(size: ShareSummaryTokens.metaSize * scale, weight: .regular))
                .foregroundStyle(Color(ShareSummaryTokens.ink2UIColor))
        }
        .frame(height: ShareSummaryTokens.metaLineHeight * scale, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeLabel(_ parts: ScheduleDateParts?) -> String {
        guard let parts else { return "—" }
        if let period = parts.periodText, !period.isEmpty {
            return "\(parts.timeText) \(period)"
        }
        return parts.timeText
    }

    private struct DurationPart {
        let text: String
        let isUnit: Bool
    }

    private func durationParts(_ compact: String) -> [DurationPart] {
        // "1h 47m" or "47:30"
        if compact.contains("h") || (compact.contains("m") && compact.contains(" ")) {
            var parts: [DurationPart] = []
            for token in compact.split(separator: " ") {
                let s = String(token)
                if s.hasSuffix("h"), !s.dropLast().isEmpty {
                    parts.append(.init(text: String(s.dropLast()), isUnit: false))
                    parts.append(.init(text: "h", isUnit: true))
                } else if s.hasSuffix("m"), !s.dropLast().isEmpty {
                    parts.append(.init(text: String(s.dropLast()), isUnit: false))
                    parts.append(.init(text: "m", isUnit: true))
                } else {
                    parts.append(.init(text: s, isUnit: false))
                }
            }
            return parts
        }
        return [.init(text: compact, isUnit: false)]
    }
}

// MARK: - Chart

private struct SummaryChartCanvas: View {
    let elevation: [HikingElevationChartSample]
    let heartRate: [HikingHeartRateChartSample]
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            let elevationMax = max(elevation.map(\.altitude).max() ?? 1, 1)
            let heartMax = max(heartRate.map(\.bpm).max() ?? 160, 80)
            let heartMin = 40.0
            let distanceMax = max(
                elevation.map(\.distanceMeters).max() ?? 0,
                heartRate.map(\.distanceMeters).max() ?? 0,
                1
            )

            func point(distance: Double, value: Double, lower: Double, upper: Double) -> CGPoint {
                let x = size.width * CGFloat(distance / distanceMax)
                let span = max(upper - lower, 1)
                let y = size.height - size.height * CGFloat((value - lower) / span)
                return CGPoint(x: x, y: min(max(y, 0), size.height))
            }

            let hair = ShareSummaryTokens.hairlineWidth(scale: scale)
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: size.height - hair / 2))
            baseline.addLine(to: CGPoint(x: size.width, y: size.height - hair / 2))
            context.stroke(baseline, with: .color(Color(ShareSummaryTokens.hairlineUIColor)), lineWidth: hair)

            if elevation.count >= 2 {
                var area = Path()
                let first = point(distance: elevation[0].distanceMeters, value: elevation[0].altitude, lower: 0, upper: elevationMax)
                area.move(to: CGPoint(x: first.x, y: size.height))
                area.addLine(to: first)
                for sample in elevation.dropFirst() {
                    area.addLine(to: point(distance: sample.distanceMeters, value: sample.altitude, lower: 0, upper: elevationMax))
                }
                if let last = elevation.last {
                    let end = point(distance: last.distanceMeters, value: last.altitude, lower: 0, upper: elevationMax)
                    area.addLine(to: CGPoint(x: end.x, y: size.height))
                }
                area.closeSubpath()
                context.fill(
                    area,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(ShareSummaryTokens.inkUIColor).opacity(0.07),
                            Color(ShareSummaryTokens.inkUIColor).opacity(0.02)
                        ]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )

                var line = Path()
                line.move(to: first)
                for sample in elevation.dropFirst() {
                    line.addLine(to: point(distance: sample.distanceMeters, value: sample.altitude, lower: 0, upper: elevationMax))
                }
                context.stroke(
                    line,
                    with: .color(Color(ShareSummaryTokens.accentUIColor)),
                    lineWidth: ShareSummaryTokens.graphElevWidth * scale
                )
            }

            if heartRate.count >= 2 {
                var line = Path()
                let first = point(distance: heartRate[0].distanceMeters, value: heartRate[0].bpm, lower: heartMin, upper: heartMax)
                line.move(to: first)
                for sample in heartRate.dropFirst() {
                    line.addLine(to: point(distance: sample.distanceMeters, value: sample.bpm, lower: heartMin, upper: heartMax))
                }
                context.stroke(
                    line,
                    with: .color(Color(ShareSummaryTokens.hrUIColor)),
                    lineWidth: ShareSummaryTokens.graphHRWidth * scale
                )
            }
        }
    }
}

#endif
