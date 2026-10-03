//
//  FlythroughLiveActivity.swift
//  SansanWidgets
//
//  3D 경로 영상 제작 진행률 — 다이나믹 아일랜드·잠금화면 Live Activity UI.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct FlythroughLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlythroughActivityAttributes.self) { context in
            FlythroughLockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.07, green: 0.13, blue: 0.09))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPaused ? "pause.circle.fill" : "video.fill")
                        .font(.title2)
                        .foregroundStyle(FlythroughActivityStyle.accent)
                        .frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(FlythroughActivityStyle.percentText(context.state.progress))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(maxHeight: .infinity)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.recordTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: context.state.progress)
                            .tint(FlythroughActivityStyle.accent)
                        Text(FlythroughActivityStyle.statusText(context.state))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "video.fill")
                    .foregroundStyle(FlythroughActivityStyle.accent)
            } compactTrailing: {
                Text(FlythroughActivityStyle.percentText(context.state.progress))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(FlythroughActivityStyle.accent)
            } minimal: {
                ProgressView(value: context.state.progress)
                    .progressViewStyle(.circular)
                    .tint(FlythroughActivityStyle.accent)
            }
        }
    }
}

private struct FlythroughLockScreenView: View {
    let context: ActivityViewContext<FlythroughActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: context.state.isPaused ? "pause.circle.fill" : "video.fill")
                    .foregroundStyle(FlythroughActivityStyle.accent)
                Text("3D 경로 영상 · \(context.attributes.recordTitle)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Text(FlythroughActivityStyle.percentText(context.state.progress))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(FlythroughActivityStyle.accent)
            }
            ProgressView(value: context.state.progress)
                .tint(FlythroughActivityStyle.accent)
            Text(FlythroughActivityStyle.statusText(context.state))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .padding(16)
    }
}

private enum FlythroughActivityStyle {
    static let accent = Color(red: 0.42, green: 0.78, blue: 0.47)

    static func percentText(_ progress: Double) -> String {
        "\(Int((min(max(progress, 0), 1) * 100).rounded()))%"
    }

    static func statusText(_ state: FlythroughActivityAttributes.ContentState) -> String {
        state.isPaused ? "일시정지됨 — 앱으로 돌아오면 이어서 만들어요" : "\(state.stageTitle) 진행 중…"
    }
}
