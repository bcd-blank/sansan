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
}
