//
//  WatchEndResumePolicyTests.swift
//  sansanTests
//
//  Watch 저장/종료 후 iPhone이 미러 백업·늦은 stop으로 기록을 이어가지 않는지.
//

import XCTest
@testable import sansan

final class WatchEndResumePolicyTests: XCTestCase {
    func testMirrorBackupClearsWhenAlreadyDismissedOrSaved() {
        let id = UUID()
        XCTAssertEqual(
            WatchEndResumePolicy.mirrorBackupAction(
                sessionID: id,
                dismissedSessionID: id,
                isAlreadySavedOrInboxed: false
            ),
            .clearOnly
        )
        XCTAssertEqual(
            WatchEndResumePolicy.mirrorBackupAction(
                sessionID: id,
                dismissedSessionID: nil,
                isAlreadySavedOrInboxed: true
            ),
            .clearOnly
        )
    }

    func testMirrorBackupDefersInsteadOfResuming() {
        XCTAssertEqual(
            WatchEndResumePolicy.mirrorBackupAction(
                sessionID: UUID(),
                dismissedSessionID: nil,
                isAlreadySavedOrInboxed: false
            ),
            .deferForWatchSync,
            "미러 백업만으로 기록 UI를 켜면 Watch 종료 후 '계속하기'가 됩니다"
        )
    }

    func testWatchOwnedStopEndsEvenWhenUnreachable() {
        XCTAssertTrue(
            WatchEndResumePolicy.shouldAcceptWatchStopAsEnd(
                liveState: .recording,
                isWatchDetachedForRecording: false,
                isPhoneRecordingFailoverActive: false,
                isWatchReachable: false,
                isWatchOwnedSession: true,
                stopCarriesFinishedSession: false
            )
        )
    }

    func testFinishedPayloadStopEndsEvenWhenUnreachable() {
        XCTAssertTrue(
            WatchEndResumePolicy.shouldAcceptWatchStopAsEnd(
                liveState: .recording,
                isWatchDetachedForRecording: false,
                isPhoneRecordingFailoverActive: false,
                isWatchReachable: false,
                isWatchOwnedSession: false,
                stopCarriesFinishedSession: true
            )
        )
    }

    func testFailoverIgnoresLateWatchStop() {
        XCTAssertFalse(
            WatchEndResumePolicy.shouldAcceptWatchStopAsEnd(
                liveState: .recording,
                isWatchDetachedForRecording: true,
                isPhoneRecordingFailoverActive: true,
                isWatchReachable: false,
                isWatchOwnedSession: true,
                stopCarriesFinishedSession: true
            ),
            "폰 인계 후에는 꺼진 Watch의 늦은 stop을 종료로 보지 않습니다"
        )
    }

    func testPhoneOwnedStopStillRequiresReachableWatch() {
        XCTAssertFalse(
            WatchEndResumePolicy.shouldAcceptWatchStopAsEnd(
                liveState: .recording,
                isWatchDetachedForRecording: false,
                isPhoneRecordingFailoverActive: false,
                isWatchReachable: false,
                isWatchOwnedSession: false,
                stopCarriesFinishedSession: false
            )
        )
        XCTAssertTrue(
            WatchEndResumePolicy.shouldAcceptWatchStopAsEnd(
                liveState: .recording,
                isWatchDetachedForRecording: false,
                isPhoneRecordingFailoverActive: false,
                isWatchReachable: true,
                isWatchOwnedSession: false,
                stopCarriesFinishedSession: false
            )
        )
    }

    func testDeferredMirrorSettlesOnlyWhenIdleUnreachableAfterGrace() {
        XCTAssertFalse(
            WatchEndResumePolicy.shouldSettleDeferredMirrorBackup(
                liveState: .recording,
                isWatchReachable: false,
                isAlreadySavedOrInboxed: false,
                deferElapsed: 120,
                settleGrace: 90
            )
        )
        XCTAssertFalse(
            WatchEndResumePolicy.shouldSettleDeferredMirrorBackup(
                liveState: .idle,
                isWatchReachable: true,
                isAlreadySavedOrInboxed: false,
                deferElapsed: 120,
                settleGrace: 90
            )
        )
        XCTAssertTrue(
            WatchEndResumePolicy.shouldSettleDeferredMirrorBackup(
                liveState: .idle,
                isWatchReachable: false,
                isAlreadySavedOrInboxed: false,
                deferElapsed: 90,
                settleGrace: 90
            )
        )
        XCTAssertTrue(
            WatchEndResumePolicy.shouldSettleDeferredMirrorBackup(
                liveState: .idle,
                isWatchReachable: true,
                isAlreadySavedOrInboxed: true,
                deferElapsed: 0,
                settleGrace: 90
            )
        )
    }
}
