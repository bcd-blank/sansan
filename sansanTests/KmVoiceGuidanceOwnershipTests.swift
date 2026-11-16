//
//  KmVoiceGuidanceOwnershipTests.swift
//  sansanTests
//
//  iPhone 빌드에서 컴파일되는 소유권 규칙(iOS 분기) 검증.
//  Watch 분기는 watchOS 타겟 단위 테스트로 보강하기 전까지 동일 시그니처로 문서화.
//

import XCTest
@testable import sansan

final class KmVoiceGuidanceOwnershipTests: XCTestCase {
    /// 시작·종료·1km 모두 동일 소유권 게이트를 씁니다.
    func testPhoneSilentWhenWatchReachable() {
        XCTAssertFalse(
            KmVoiceGuidanceOwnership.shouldSpeakLocally(
                recordingStartedOnWatch: false,
                isCounterpartReachable: true
            )
        )
        XCTAssertFalse(
            KmVoiceGuidanceOwnership.shouldSpeakLocally(
                recordingStartedOnWatch: true,
                isCounterpartReachable: true
            )
        )
    }

    func testPhoneSpeaksWhenWatchUnreachable() {
        XCTAssertTrue(
            KmVoiceGuidanceOwnership.shouldSpeakLocally(
                recordingStartedOnWatch: false,
                isCounterpartReachable: false
            )
        )
        XCTAssertTrue(
            KmVoiceGuidanceOwnership.shouldSpeakLocally(
                recordingStartedOnWatch: true,
                isCounterpartReachable: false
            )
        )
    }

    func testStartAndEndOwnershipMatchesKilometerAlerts() {
        // iPhone 시작 + Watch reachable → iPhone 침묵(Watch가 시작/종료 말함)
        XCTAssertFalse(
            KmVoiceGuidanceOwnership.shouldSpeakLocally(
                recordingStartedOnWatch: false,
                isCounterpartReachable: true
            )
        )
        // iPhone 시작 + Watch unreachable → iPhone이 시작/종료 말함
        XCTAssertTrue(
            KmVoiceGuidanceOwnership.shouldSpeakLocally(
                recordingStartedOnWatch: false,
                isCounterpartReachable: false
            )
        )
        // Watch 시작 + Watch unreachable(핸드오프) → iPhone이 이어받음
        XCTAssertTrue(
            KmVoiceGuidanceOwnership.shouldSpeakLocally(
                recordingStartedOnWatch: true,
                isCounterpartReachable: false
            )
        )
    }
}
