//
//  HikingRecordSummaryShareComposer.swift
//  sansan
//
//  9:16 지도 한 장 위에 기록 정보를 흰 글자로 올리고, 타이틀과 정보 뒤에만 음영을 둡니다.
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
        let canvas = CGSize(width: width, height: width * 16 / 9)
        let scale = HikingRecordShareDeviceMetrics.nativeScale
        let hasMemo = !(record.memo?.isEmpty ?? true)
        let pinnedCount = mapOptions.showsPinnedThumbnails ? record.mapPinnedPhotos.count : 0
        var captureOptions = mapOptions
        captureOptions.showsPinnedThumbnails = false
        guard let map = await HikingRouteSnapshotGenerator.fittedMapImage(
            record: record,
            canvasSize: canvas,
            pixelScale: scale,
            mapOptions: captureOptions,
            insetTop: summaryMemoBottom(canvasWidth: canvas.width, hasMemo: hasMemo) + summaryRouteMarkerPad,
            insetBottom: summaryDistanceInset() + summaryRouteMarkerPad,
            insetLeft: summaryRouteEdgePad,
            insetRight: summaryRouteEdgePad,
            routeFillFraction: 1
        ) else { return nil }

        let page = SummaryMapSharePage(
            record: record,
            mapImage: map,
            showsPinnedThumbnails: pinnedCount > 0
        )
            .frame(width: canvas.width, height: canvas.height)
        let renderer = ImageRenderer(content: page)
        renderer.proposedSize = ProposedViewSize(width: canvas.width, height: canvas.height)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// 로고 줄, 타이틀, 메모가 경로와 겹치지 않도록 위쪽을 비웁니다.
/// 2행이던 메모가 길면 글자를 80%까지 줄여 그리던 크기.
private let summaryMemoFontScale: CGFloat = 0.8
private let summaryMemoLineBox: CGFloat = 4.2
private let summaryPinnedThumbTopDrop: CGFloat = 16
private let summaryRouteEdgePad: CGFloat = 36
private let summaryRouteMarkerPad: CGFloat = 28
private let summaryHeaderTopPad: CGFloat = 22
private let summaryHeaderSidePad: CGFloat = 20

/// 메모(없으면 제목) 하단. 경로는 여기서부터 거리 숫자 위까지 채웁니다.
private func summaryMemoBottom(canvasWidth: CGFloat, hasMemo: Bool) -> CGFloat {
    let layoutScale = canvasWidth / RouteBrandLogoMetrics.referenceCanvasWidth
    let logoHeight = RouteBrandLogoMetrics.side * layoutScale * 0.64 / RouteBrandLogoMetrics.artworkAspect
    let titleHeight = max(24, canvasWidth * 0.064) * 1.15
    var height = summaryHeaderTopPad + logoHeight + 8 + titleHeight
    if hasMemo {
        height += 8 + max(13, canvasWidth * 0.032) * summaryMemoFontScale * summaryMemoLineBox
    }
    return height
}

/// 화면 하단에서 거리 라벨 상단까지의 높이.
private func summaryDistanceInset() -> CGFloat {
    let distance = 12 * 1.2 + 2 + 52 * 1.2
    let metrics = 11 * 1.2 + 3 + 18 * 1.2
    let caption = 12 * 1.2
    let chart = 11 * 1.2 + 8 + 64
    return 36 + distance + 16 + metrics + 16 + caption + 16 + chart
}

private func summaryHeaderClearance(canvasWidth: CGFloat, hasMemo: Bool, pinnedCount: Int = 0) -> CGFloat {
    let layoutScale = canvasWidth / RouteBrandLogoMetrics.referenceCanvasWidth
    let logoHeight = RouteBrandLogoMetrics.side * layoutScale * 0.64 / RouteBrandLogoMetrics.artworkAspect
    var textHeight = summaryMemoBottom(canvasWidth: canvasWidth, hasMemo: hasMemo) + 12
    guard pinnedCount > 0 else { return textHeight }
    let scale = canvasWidth / 377
    let chip = (64 + 10) * scale
    let stack = 8 + summaryPinnedThumbTopDrop + CGFloat(pinnedCount) * chip + CGFloat(pinnedCount - 1) * 7 * scale
    let railHeight = summaryHeaderTopPad + logoHeight + stack + 12
    return max(textHeight, railHeight)
}

private struct SummaryMapSharePage: View {
    let record: SavedHikingSession
    let mapImage: UIImage
    var showsPinnedThumbnails: Bool = false

    private var showsWeather: Bool {
        HikingShareExportPreferences.mapOptions.showsWeatherLabel && record.weather != nil
    }

    var body: some View {
        ZStack {
            Image(uiImage: mapImage)
                .resizable()
                .frame(width: mapImage.size.width, height: mapImage.size.height)

            topScrim
            bottomScrim

            headerLine
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            SummaryInfoBlock(record: record)
                .padding(.horizontal, 22)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: mapImage.size.width, height: mapImage.size.height)
        .clipped()
    }

    /// 타이틀을 덮고, 경로가 시작되는 지점에서 투명해진다.
    private var topScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.62), location: 0),
                .init(color: .black.opacity(0.46), location: 0.55),
                .init(color: .black.opacity(0.20), location: 0.78),
                .init(color: .black.opacity(0.05), location: 0.92),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: summaryHeaderClearance(
            canvasWidth: mapImage.size.width,
            hasMemo: !(record.memo?.isEmpty ?? true),
            pinnedCount: showsPinnedThumbnails ? record.mapPinnedPhotos.count : 0
        ) + mapImage.size.height * 0.07)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    /// 거리 숫자까지 진하게 덮고, 그 위에서 경로 쪽으로 사라진다.
    private var bottomScrim: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.04), location: 0.10),
                .init(color: .black.opacity(0.20), location: 0.18),
                .init(color: .black.opacity(0.40), location: 0.28),
                .init(color: .black.opacity(0.48), location: 0.38),
                .init(color: .black.opacity(0.50), location: 0.52),
                .init(color: .black.opacity(0.50), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: mapImage.size.height * 0.56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private var headerLine: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                summaryLogo
                Spacer(minLength: 8)
                if showsWeather, let weather = record.weather {
                    HikingRecordMapWeatherOverlay(
                        weather: weather,
                        layoutScale: mapImage.size.width / HikingRecordCardLayout.referenceContentWidth * 0.72,
                        summaryMaxWidth: mapImage.size.width * 0.5
                    )
                    .frame(maxWidth: mapImage.size.width * 0.5, alignment: .trailing)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.exportCardTitle)
                        .font(.system(size: max(24, mapImage.size.width * 0.064), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .summaryTextShadow()
                    if let memo = record.memo, !memo.isEmpty {
                        Text(memo)
                            .font(.system(size: max(13, mapImage.size.width * 0.032) * summaryMemoFontScale, weight: .medium))
                            .foregroundStyle(.white.opacity(0.84))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .summaryTextShadow()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsPinnedThumbnails {
                    VStack(spacing: 7 * mapImage.size.width / 377) {
                        ForEach(record.mapPinnedPhotos) { photo in
                            SummaryPinnedThumbnailChip(recordID: record.id, photo: photo, canvasWidth: mapImage.size.width)
                        }
                    }
                    .padding(.top, summaryPinnedThumbTopDrop)
                    .frame(width: (64 + 10) * mapImage.size.width / 377)
                }
            }
        }
        .padding(.top, summaryHeaderTopPad)
        .padding(.horizontal, summaryHeaderSidePad)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryLogo: some View {
        let layoutScale = mapImage.size.width / RouteBrandLogoMetrics.referenceCanvasWidth
        let logoWidth = RouteBrandLogoMetrics.side * layoutScale * 0.64
        let logoHeight = logoWidth / RouteBrandLogoMetrics.artworkAspect
        return Image("SansanLogoSymbol")
            .resizable()
            .aspectRatio(RouteBrandLogoMetrics.artworkAspect, contentMode: .fit)
            .frame(width: logoWidth, height: logoHeight)
            .shadow(color: .black.opacity(0.28), radius: 6, y: 2)
    }
}

private struct SummaryPinnedThumbnailChip: View {
    let recordID: UUID
    let photo: HikingTrailPhoto
    let canvasWidth: CGFloat

    private var scale: CGFloat { canvasWidth / 377 }
    private var imageSide: CGFloat { 64 * scale }
    private var ring: CGFloat { 5 * scale }

    private var image: UIImage? {
        HikingTrailPhotoStore.loadImage(sessionID: recordID, filename: photo.filename)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.38))
                .frame(width: imageSide + ring * 2, height: imageSide + ring * 2)
            Circle()
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                .frame(width: imageSide + ring * 2, height: imageSide + ring * 2)
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.tertiarySystemFill)
                }
            }
            .frame(width: imageSide, height: imageSide)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.85), lineWidth: 2 * scale)
            }
        }
        .shadow(color: .black.opacity(0.22), radius: 8 * scale, y: 3 * scale)
    }
}

private struct SummaryInfoBlock: View {
    let record: SavedHikingSession

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("거리")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(record.distanceValueText)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(record.distanceUnitText)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .summaryTextShadow()

            HStack(alignment: .top, spacing: 0) {
                valueColumn(label: "시간", value: record.formattedDurationCompact, unit: "")
                valueColumn(label: "상승", value: record.elevationValueText, unit: "m")
                valueColumn(
                    label: "평균속도",
                    value: record.averageSpeedValueText,
                    unit: record.averageSpeedUnitText
                )
            }
            .summaryTextShadow()

            Text(captionLine)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .summaryTextShadow()

            SummaryElevationHeartChart(
                elevation: elevationSamples,
                heartRate: heartSamples
            )
        }
        .foregroundStyle(.white)
    }

    private var captionLine: String {
        let end = record.endedScheduleParts
        let start = record.startedScheduleParts
        let startTime = timeLabel(start)
        let endTime = timeLabel(end)
        return "\(startTime) – \(endTime)   ·   \(record.stepCountValueText) 걸음   ·   \(record.caloriesValueText) kcal"
    }

    private func timeLabel(_ parts: ScheduleDateParts?) -> String {
        guard let parts else { return "—" }
        if let period = parts.periodText, !period.isEmpty {
            return "\(parts.timeText) \(period)"
        }
        return parts.timeText
    }

    private func valueColumn(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SummaryElevationHeartChart: View {
    let elevation: [HikingElevationChartSample]
    let heartRate: [HikingHeartRateChartSample]

    private var maxElevation: Int {
        Int((elevation.map(\.altitude).max() ?? 0).rounded())
    }

    private var heartStats: (average: Int, minimum: Int, maximum: Int)? {
        let values = heartRate.map(\.bpm)
        guard let minValue = values.min(), let maxValue = values.max(), !values.isEmpty else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        return (Int(average.rounded()), Int(minValue.rounded()), Int(maxValue.rounded()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("고도 \(maxElevation) m")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                if let heartStats {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.4))
                    Text("심박 \(heartStats.average)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("\(heartStats.minimum)–\(heartStats.maximum)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
            .monospacedDigit()
            .summaryTextShadow()

            SummaryChartCanvas(elevation: elevation, heartRate: heartRate)
                .frame(height: 64)
        }
    }
}

private struct SummaryChartCanvas: View {
    let elevation: [HikingElevationChartSample]
    let heartRate: [HikingHeartRateChartSample]

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
                context.fill(area, with: .color(.white.opacity(0.16)))

                var line = Path()
                line.move(to: first)
                for sample in elevation.dropFirst() {
                    line.addLine(to: point(distance: sample.distanceMeters, value: sample.altitude, lower: 0, upper: elevationMax))
                }
                context.stroke(line, with: .color(.white.opacity(0.92)), lineWidth: 1.5)
            }

            if heartRate.count >= 2 {
                var line = Path()
                let first = point(distance: heartRate[0].distanceMeters, value: heartRate[0].bpm, lower: heartMin, upper: heartMax)
                line.move(to: first)
                for sample in heartRate.dropFirst() {
                    line.addLine(to: point(distance: sample.distanceMeters, value: sample.bpm, lower: heartMin, upper: heartMax))
                }
                context.stroke(line, with: .color(.white.opacity(0.55)), lineWidth: 1.15)
            }
        }
    }
}

private extension View {
    func summaryTextShadow() -> some View {
        shadow(color: .black.opacity(0.28), radius: 1.5, y: 1)
            .shadow(color: .black.opacity(0.20), radius: 10, y: 3)
    }
}

#endif
