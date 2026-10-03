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
    @ObservedObject private var heartRatePreferences = HeartRatePreferencesObserver.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            content
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
        HStack(spacing: 10) {
            Label("심박수", systemImage: "heart.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.pink)

            Spacer()

            if heartRatePreferences.isMonitoringEnabled {
                if let current = workout.sessionData.currentHeartRate {
                    Text("\(Int(current.rounded())) bpm")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.pink)
                } else if let average = workout.sessionData.averageHeartRate {
                    Text("평균 \(Int(average.rounded()))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                Text("측정")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Toggle("", isOn: monitoringBinding)
                    .labelsHidden()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if heartRatePreferences.isMonitoringEnabled {
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
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "heart.text.square",
                    description: Text(emptyDescription)
                )
                .frame(height: 120)
            }
        } else {
            Text("측정을 켜면 Apple Watch에서 실시간 심박을 기록합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 72, alignment: .topLeading)
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

    private var monitoringBinding: Binding<Bool> {
        Binding(
            get: { heartRatePreferences.isMonitoringEnabled },
            set: { isOn in
                Task {
                    await workout.setHeartRateMonitoringEnabled(isOn)
                }
            }
        )
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
