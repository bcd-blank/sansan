//
//  DashboardElevationProfileCard.swift
//  sansan
//
//  메인 화면 고도 프로필 카드 — 저장된 GPS 포인트 기준 거리·고도 차트.
//

#if os(iOS)

import Charts
import SwiftUI

struct DashboardElevationProfileCard: View {
    @Binding var elevationGainText: String

    @ObservedObject private var workout = WorkoutManager.shared
    @State private var chartPoints: [DashboardElevationChartPoint] = []

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                headerRow
                chartContent
            }
            if chartPoints.count < 2 {
                DashboardChartEmptyPlaceholder(
                    systemImage: "chart.xyaxis.line",
                    title: emptyTitle,
                    description: emptyDescription,
                    descriptionLineReserve: 2
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .onAppear {
            rebuildChartData()
        }
        .onChange(of: workout.sessionData.points.count) { _, _ in
            rebuildChartData()
        }
    }

    private var headerRow: some View {
        DashboardChartCardHeader(
            title: "고도",
            systemImage: "chart.xyaxis.line",
            tint: .orange,
            trailing: chartPoints.last.map { "\(Int($0.altitude)) m" }
        )
    }

    @ViewBuilder
    private var chartContent: some View {
        if chartPoints.count >= 2 {
            let axis = elevationAxis
            Chart(chartPoints) { point in
                LineMark(
                    x: .value("거리", point.distanceKilometers),
                    y: .value("고도", point.altitude)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(.orange.gradient)

                AreaMark(
                    x: .value("거리", point.distanceKilometers),
                    yStart: .value("기준", axis.domain.lowerBound),
                    yEnd: .value("고도", point.altitude)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(.orange.opacity(0.18))
            }
            .chartXAxis(.hidden)
            .chartYScale(domain: axis.domain)
            .chartYAxis {
                AxisMarks(position: .leading, values: axis.ticks) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let meters = value.as(Double.self) {
                            Text("\(Int(meters.rounded()))")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartPlotStyle { plot in
                plot.padding(.bottom, 6)
            }
            .frame(height: 120)
        } else {
            Color.clear.frame(height: 120)
        }
    }

    private var elevationAxis: ElevationChartYAxisSpec {
        let altitudes = chartPoints.map(\.altitude)
        return ElevationChartYAxisSpec.fitting(
            minAltitude: altitudes.min() ?? 0,
            maxAltitude: altitudes.max() ?? 0
        )
    }

    private var emptyTitle: String {
        switch workout.sessionData.state {
        case .idle:
            return "고도 데이터 없음"
        case .recording, .paused:
            return "고도 수집 중"
        }
    }

    private var emptyDescription: String {
        switch workout.sessionData.state {
        case .idle:
            return "기록을 시작하면 고도 그래프가 표시됩니다."
        case .recording, .paused:
            return "GPS 포인트가 쌓이면 고도 그래프가 표시됩니다."
        }
    }

    private func rebuildChartData() {
        let points = workout.sessionData.points
        if let altitude = HikingSessionMetrics.stationaryAltitude(from: points) {
            chartPoints = [
                DashboardElevationChartPoint(id: UUID(), distanceKilometers: 0, altitude: altitude),
                DashboardElevationChartPoint(id: UUID(), distanceKilometers: 1, altitude: altitude),
            ]
            elevationGainText = "0"
            return
        }
        chartPoints = HikingSessionMetrics.elevationProfileSamples(from: points).map { sample in
            DashboardElevationChartPoint(
                id: sample.id,
                distanceKilometers: sample.distanceMeters / 1_000,
                altitude: sample.altitude
            )
        }
        let gain = HikingSessionMetrics.cumulativeElevationGain(from: points)
        elevationGainText = String(format: "%.0f", gain)
    }
}

/// 고도·심박 카드가 같은 아이콘 칸과 제목 시작 위치를 쓰도록 헤더를 하나로 둡니다.
struct DashboardChartCardHeader: View {
    let title: String
    let systemImage: String
    let tint: Color
    var trailing: String? = nil
    var trailingColor: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .foregroundStyle(tint)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(trailingColor)
                    .lineLimit(1)
            }
        }
    }
}

struct DashboardChartEmptyPlaceholder: View {
    var systemImage: String? = nil
    let title: String
    let description: String
    /// 1이면 문구 길이대로, 2면 두 줄 높이를 비워 카드마다 제목이 위아래로 밀리지 않습니다.
    var descriptionLineReserve: Int = 1

    private let iconSize: CGFloat = 20

    var body: some View {
        VStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.monochrome)
            }
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                descriptionText
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var descriptionText: some View {
        let text = Text(description)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        if descriptionLineReserve > 1 {
            text.lineLimit(descriptionLineReserve, reservesSpace: true)
        } else {
            text
        }
    }
}

private struct DashboardElevationChartPoint: Identifiable {
    let id: UUID
    let distanceKilometers: Double
    let altitude: Double
}

#endif
