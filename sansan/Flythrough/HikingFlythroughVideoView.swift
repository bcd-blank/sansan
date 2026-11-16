//
//  HikingFlythroughVideoView.swift
//  sansan
//
//  3D 경로 영상 생성 진행 표시 → 미리보기/공유 화면.
//

#if os(iOS)

import AVKit
import SwiftUI

struct HikingFlythroughVideoView: View {
    let phase: FlythroughProgressPhase
    let videoURL: URL?
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .finished where videoURL != nil:
                preview(url: videoURL!)
            case .failed(let message):
                failure(message: message)
            default:
                progress
            }
        }
        .fontDesign(.rounded)
    }

    // MARK: - Progress

    private var progress: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 56)

            progressHeader

            Spacer(minLength: 40)

            pipelineTimeline
                .padding(.horizontal, 32)

            Spacer(minLength: 28)

            progressGuidance
                .padding(.horizontal, 40)

            Spacer(minLength: 20)

            cancelButton
                .padding(.horizontal, 32)
                .padding(.bottom, 28)
        }
    }

    private var progressGuidance: some View {
        VStack(spacing: 6) {
            Text("화면을 켜 둔 채로 잠시 기다려 주세요.")
                .font(.footnote)
                .foregroundStyle(FlythroughLoadingStyle.textTertiary)
                .multilineTextAlignment(.center)

            Text("화면을 닫거나 다른 화면으로 이동하면 제작이 일시정지되고 다시 돌아오면 재개됩니다.")
                .font(.caption)
                .foregroundStyle(FlythroughLoadingStyle.textTertiary.opacity(0.85))
                .multilineTextAlignment(.center)
            
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "화면을 켜 둔 채로 잠시 기다려 주세요. 화면을 닫거나 다른 화면으로 이동하면 제작이 취소됩니다."
        )
    }

    private var progressHeader: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(FlythroughLoadingStyle.track, lineWidth: 3)
                    .frame(width: 88, height: 88)
                Circle()
                    .trim(from: 0, to: phase.fraction)
                    .stroke(
                        FlythroughLoadingStyle.accent,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 88, height: 88)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.35), value: phase.fraction)

                Text("\(Int(phase.fraction * 100))")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(FlythroughLoadingStyle.textPrimary)
                    .monospacedDigit()
            }

            VStack(spacing: 5) {
                Text("3D 경로 영상")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FlythroughLoadingStyle.textPrimary)

                Text(phase.currentStep.title)
                    .font(.footnote)
                    .foregroundStyle(FlythroughLoadingStyle.accent)

                Text(phase.message)
                    .font(.footnote)
                    .foregroundStyle(FlythroughLoadingStyle.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("3D 경로 영상 \(Int(phase.fraction * 100))%, \(phase.currentStep.title)")
    }

    private var pipelineTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(FlythroughPipelineStep.allCases.enumerated()), id: \.element) { index, step in
                timelineRow(
                    step: step,
                    isLast: index == FlythroughPipelineStep.allCases.count - 1
                )
            }
        }
    }

    private func timelineRow(step: FlythroughPipelineStep, isLast: Bool) -> some View {
        let status = phase.status(for: step)
        let stepFraction = phase.progress(for: step)
        let isActive = status == .active

        return HStack(alignment: .top, spacing: 14) {
            timelineRail(status: status, isLast: isLast, isActive: isActive)

            VStack(alignment: .leading, spacing: isActive ? 10 : 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(step.title)
                        .font(isActive ? .subheadline.weight(.semibold) : .subheadline)
                        .foregroundStyle(titleColor(for: status))

                    Spacer(minLength: 8)

                    if isActive {
                        Text("\(Int(stepFraction * 100))%")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(FlythroughLoadingStyle.textSecondary)
                            .monospacedDigit()
                    }
                }

                if isActive {
                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(FlythroughLoadingStyle.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    stepProgressBar(fraction: stepFraction)
                }
            }
            .padding(.bottom, isLast ? 0 : (isActive ? 22 : 14))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: step, status: status, progress: stepFraction))
    }

    private func timelineRail(status: FlythroughStepStatus, isLast: Bool, isActive: Bool) -> some View {
        VStack(spacing: 0) {
            timelineNode(status: status, isActive: isActive)
                .frame(width: 20, height: 20)

            if !isLast {
                Rectangle()
                    .fill(connectorColor(for: status))
                    .frame(width: 1.5)
                    .frame(maxHeight: isActive ? 44 : 28)
                    .padding(.top, 4)
            }
        }
        .frame(width: 20)
    }

    @ViewBuilder
    private func timelineNode(status: FlythroughStepStatus, isActive: Bool) -> some View {
        switch status {
        case .completed:
            Circle()
                .fill(FlythroughLoadingStyle.accent.opacity(0.9))
                .frame(width: 8, height: 8)
                .frame(width: 20, height: 20)
        case .active:
            ZStack {
                Circle()
                    .stroke(FlythroughLoadingStyle.accent.opacity(0.35), lineWidth: 6)
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(FlythroughLoadingStyle.accent)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 20, height: 20)
        case .pending:
            Circle()
                .stroke(FlythroughLoadingStyle.textTertiary, lineWidth: 1.5)
                .frame(width: 8, height: 8)
                .frame(width: 20, height: 20)
        }
    }

    private func stepProgressBar(fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(FlythroughLoadingStyle.track)
                Capsule()
                    .fill(FlythroughLoadingStyle.accent.opacity(0.92))
                    .frame(
                        width: max(
                            proxy.size.width * min(max(fraction, 0), 1),
                            fraction > 0 ? 2 : 0
                        )
                    )
            }
        }
        .frame(height: 2)
        .animation(.easeInOut(duration: 0.3), value: fraction)
    }

    private func titleColor(for status: FlythroughStepStatus) -> Color {
        switch status {
        case .completed: return FlythroughLoadingStyle.textSecondary
        case .active: return FlythroughLoadingStyle.textPrimary
        case .pending: return FlythroughLoadingStyle.textTertiary
        }
    }

    private func connectorColor(for status: FlythroughStepStatus) -> Color {
        switch status {
        case .completed: return FlythroughLoadingStyle.accent.opacity(0.35)
        case .active: return FlythroughLoadingStyle.track
        case .pending: return FlythroughLoadingStyle.track
        }
    }

    private var cancelButton: some View {
        Button(role: .cancel, action: onCancel) {
            Text("취소")
                .font(.body.weight(.medium))
                .foregroundStyle(FlythroughLoadingStyle.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FlythroughLoadingStyle.track, lineWidth: 1)
                )
        }
    }

    private func accessibilityLabel(
        for step: FlythroughPipelineStep,
        status: FlythroughStepStatus,
        progress: Double
    ) -> String {
        let percent = Int(progress * 100)
        switch status {
        case .completed: return "\(step.title), 완료"
        case .active: return "\(step.title), 진행 중 \(percent)%, \(step.detail)"
        case .pending: return "\(step.title), 대기"
        }
    }

    // MARK: - Failure

    private func failure(message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 40)
            Spacer()
            VStack(spacing: 12) {
                Button(action: onRetry) {
                    Text("다시 시도")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.orange, in: Capsule())
                }
                Button(action: onClose) {
                    Text("닫기")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Preview

    private func preview(url: URL) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.15), in: Circle())
                }
                Spacer()
                Text("3D 경로 영상")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            LoopingVideoPlayer(url: url)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 16)

            Button {
                ActivitySharePresenter.present(items: [url], mode: .recordCard)
            } label: {
                Label("영상 공유", systemImage: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange, in: Capsule())
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Loading style

private enum FlythroughLoadingStyle {
    static let accent = Color.orange
    static let track = Color.white.opacity(0.10)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.30)
}

/// 자동 재생 + 무한 반복 비디오 플레이어.
private struct LoopingVideoPlayer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        controller.player = player
        player.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        controller.player = player
        player.play()
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator {
        var looper: AVPlayerLooper?
        var url: URL
        init(url: URL) { self.url = url }
    }
}

#endif
