//
//  WorkoutEndingGate.swift
//  Shared
//
//  종료·요약 저장의 비동기 걸음 조회가 다른 세대 세션을 건드리지 못하게 하는 순수 가드.
//

import Foundation

enum WorkoutEndingGate {
    /// `finalizeStepCount` await 뒤 — 같은 요약 세션이 아직 검토 중일 때만 걸음수를 반영합니다.
    static func shouldApplySummaryStepCount(
        expectedSessionID: UUID,
        currentSummarySessionID: UUID?,
        isAwaitingSummaryConfirmation: Bool
    ) -> Bool {
        isAwaitingSummaryConfirmation && currentSummarySessionID == expectedSessionID
    }

    /// 저장 완료·원격 종료 완료 후 — 이미 새 기록이 시작됐으면 live 세션·백업을 지우지 않습니다.
    static func shouldResetSessionToIdle(liveState: HikingSessionState) -> Bool {
        liveState == .idle
    }
}
