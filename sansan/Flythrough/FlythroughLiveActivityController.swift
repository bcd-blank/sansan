//
//  FlythroughLiveActivityController.swift
//  sansan
//
//  영상 제작 진행률을 다이나믹 아일랜드·잠금화면 Live Activity로 중계합니다.
//

#if os(iOS)

import ActivityKit
import Foundation

@MainActor
final class FlythroughLiveActivityController {
    private var activity: Activity<FlythroughActivityAttributes>?
    private var lastPhase: FlythroughProgressPhase = .preparing(.analyzeRoute, progress: 0)
    private var isPaused = false
    private var lastSentAt = Date.distantPast
    private var lastSentProgress: Double = -1
    private var lastSentStage = ""
    private var lastSentPaused = false

    func start(recordTitle: String) {
        endImmediately()
        guard FlythroughCapabilities.isFeatureEnabled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        lastPhase = .preparing(.analyzeRoute, progress: 0)
        isPaused = false
        let state = FlythroughActivityAttributes.ContentState(
            progress: 0,
            stageTitle: FlythroughPipelineStep.analyzeRoute.title,
            isPaused: false
        )
        activity = try? Activity.request(
            attributes: FlythroughActivityAttributes(recordTitle: recordTitle),
            content: ActivityContent(state: state, staleDate: nil)
        )
        lastSentAt = Date()
        lastSentProgress = 0
        lastSentStage = state.stageTitle
        lastSentPaused = false
    }

    func update(phase: FlythroughProgressPhase) {
        lastPhase = phase
        send()
    }

    /// 앱 백그라운드 전환 시 "일시정지" 상태를 즉시 반영합니다(이후 앱이 곧 중단되므로 스로틀 없음).
    func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        isPaused = paused
        send(force: true)
    }

    /// 완료·실패·취소 시 Live Activity를 종료합니다.
    func stop() {
        endImmediately()
    }

    private func send(force: Bool = false) {
        guard let activity else { return }
        let progress = min(max(lastPhase.fraction, 0), 1)
        let stage = lastPhase.currentStep.title
        let now = Date()
        // ActivityKit 업데이트 예산 보호 — 의미 있는 변화 또는 1초 경과 시에만 전송.
        if !force,
           stage == lastSentStage,
           isPaused == lastSentPaused,
           now.timeIntervalSince(lastSentAt) < 1,
           abs(progress - lastSentProgress) < 0.05 {
            return
        }
        lastSentAt = now
        lastSentProgress = progress
        lastSentStage = stage
        lastSentPaused = isPaused
        let state = FlythroughActivityAttributes.ContentState(
            progress: progress,
            stageTitle: stage,
            isPaused: isPaused
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private func endImmediately() {
        guard let activity else { return }
        self.activity = nil
        let state = FlythroughActivityAttributes.ContentState(
            progress: 1,
            stageTitle: FlythroughPipelineStep.encodeVideo.title,
            isPaused: false
        )
        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }
}

#endif
