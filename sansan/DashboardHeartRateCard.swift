//
//  DashboardHeartRateCard.swift
//  sansan
//
//  메인 화면 심박수 카드 — 고도 프로필 아래 표시.
//

#if os(iOS)

import Charts
import SwiftUI

struct DashboardHeartRateCard: View {
    @ObservedObject private var workout = WorkoutManager.shared

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                headerRow
                chartContent
            }
            if chartPoints.count < 2 {
                DashboardChartEmptyPlaceholder(
                    systemImage: "heart.fill",
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
    }

    private var headerRow: some View {
        DashboardChartCardHeader(
            title: "심박수",
            systemImage: "heart.fill",
            tint: .pink,
            trailing: trailingText,
            trailingColor: workout.sessionData.currentHeartRate == nil ? .secondary : .pink
        )
    }

    private var trailingText: String? {
        if let current = workout.sessionData.currentHeartRate {
            return "\(Int(current.rounded())) bpm"
        }
        if let average = workout.sessionData.averageHeartRate {
            return "평균 \(Int(average.rounded()))"
        }
        return nil
    }

    @ViewBuilder
    private var chartContent: some View {
        if chartPoints.count >= 2 {
            Chart(chartPoints) { point in
                LineMark(
                    x: .value("시간", point.elapsedMinutes),
                    y: .value("심박", point.bpm)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.pink.gradient)

                AreaMark(
                    x: .value("시간", point.elapsedMinutes),
                    y: .value("심박", point.bpm)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.pink.opacity(0.16))
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let bpm = value.as(Double.self) {
                            Text("\(Int(bpm))")
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

    private var chartPoints: [DashboardHeartRateChartPoint] {
        guard let startedAt = workout.sessionData.effectiveStartedAt else { return [] }
        return workout.sessionData.heartRateSamples.map { sample in
            DashboardHeartRateChartPoint(
                id: sample.id,
                elapsedMinutes: sample.timestamp.timeIntervalSince(startedAt) / 60,
                bpm: sample.bpm
            )
        }
    }

    private var emptyTitle: String {
        switch workout.sessionData.state {
        case .idle:
            return "심박수 대기 중"
        case .recording, .paused:
            return "심박수 수집 중"
        }
    }

    private var emptyDescription: String {
        switch workout.sessionData.state {
        case .idle:
            return "기록을 시작하고 Apple Watch를 착용하면 심박 그래프가 표시됩니다."
        case .recording, .paused:
            return "Apple Watch를 착용하면 실시간 심박 그래프가 표시됩니다."
        }
    }
}

private struct DashboardHeartRateChartPoint: Identifiable {
    let id: UUID
    let elapsedMinutes: Double
    let bpm: Double
}

#endif
