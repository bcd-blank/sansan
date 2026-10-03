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
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            chartContent
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
        HStack {
            Label("고도 프로필", systemImage: "chart.xyaxis.line")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if let last = chartPoints.last {
                Text("\(Int(last.altitude)) m")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
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
            ContentUnavailableView(
                emptyTitle,
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text(emptyDescription)
            )
            .frame(height: 120)
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

private struct DashboardElevationChartPoint: Identifiable {
    let id: UUID
    let distanceKilometers: Double
    let altitude: Double
}

#endif
