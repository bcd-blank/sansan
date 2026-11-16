//
//  WorkoutEndingGateTests.swift
//  sansanTests
//
//  B01 — 늦은 걸음 조회·저장 연타가 다른 세대 세션을 건드리지 않는지.
//

import XCTest
@testable import sansan

final class WorkoutEndingGateTests: XCTestCase {
    func testApplySummaryStepsRequiresSameAwaitingSession() {
        let id = UUID()
        XCTAssertTrue(
            WorkoutEndingGate.shouldApplySummaryStepCount(
                expectedSessionID: id,
                currentSummarySessionID: id,
                isAwaitingSummaryConfirmation: true
            )
        )
        XCTAssertFalse(
            WorkoutEndingGate.shouldApplySummaryStepCount(
                expectedSessionID: id,
                currentSummarySessionID: id,
                isAwaitingSummaryConfirmation: false
            ),
            "삭제·저장 완료 뒤에는 요약을 되살리면 안 됩니다"
        )
        XCTAssertFalse(
            WorkoutEndingGate.shouldApplySummaryStepCount(
                expectedSessionID: id,
                currentSummarySessionID: UUID(),
                isAwaitingSummaryConfirmation: true
            ),
            "다른 요약 세션에는 걸음수를 넣으면 안 됩니다"
        )
        XCTAssertFalse(
            WorkoutEndingGate.shouldApplySummaryStepCount(
                expectedSessionID: id,
                currentSummarySessionID: nil,
                isAwaitingSummaryConfirmation: true
            )
        )
    }

    func testResetToIdleOnlyWhenLiveSessionStillIdle() {
        XCTAssertTrue(WorkoutEndingGate.shouldResetSessionToIdle(liveState: .idle))
        XCTAssertFalse(
            WorkoutEndingGate.shouldResetSessionToIdle(liveState: .recording),
            "저장 완료 중 시작한 새 기록을 resetSessionToIdle이 지우면 안 됩니다"
        )
        XCTAssertFalse(WorkoutEndingGate.shouldResetSessionToIdle(liveState: .paused))
    }
}
