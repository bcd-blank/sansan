//
//  KmVoiceGuidanceControllerTests.swift
//  sansanTests
//
//  시뮬레이터에서 1–3km 가짜 거리 진행 시 구간 시간 문구가  Speaks/로그되는지 검증.
//

#if os(iOS)

import XCTest
@testable import sansan

@MainActor
final class KmVoiceGuidanceControllerTests: XCTestCase {
    override func setUp() async throws {
        KmVoiceGuidancePreferences.isEnabled = true
        KmVoiceGuidanceController.shared.clear()
    }

    override func tearDown() async throws {
        KmVoiceGuidanceController.shared.clear()
    }

    func testAnnouncesEachKilometerWithSegmentTime() {
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.prepareForNewSession(sessionID)

        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 1_000,
            activeElapsed: 720,
            state: .recording
        )
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 2_000,
            activeElapsed: 1_500,
            state: .recording
        )
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 3_050,
            activeElapsed: 2_100,
            state: .recording
        )

        XCTAssertEqual(
            controller.spokenPhrasesLog,
            [
                "1킬로미터 지점입니다. 이번 구간 12분, 총 산행 시간 12분입니다.",
                "2킬로미터 지점입니다. 이번 구간 13분, 총 산행 시간 25분입니다.",
                "3킬로미터 지점입니다. 이번 구간 10분, 총 산행 시간 35분입니다.",
            ]
        )
    }

    func testDoesNotAnnounceWhilePaused() {
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.prepareForNewSession(sessionID)

        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 1_200,
            activeElapsed: 600,
            state: .paused
        )
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)

        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 1_200,
            activeElapsed: 600,
            state: .recording
        )
        XCTAssertEqual(controller.spokenPhrasesLog.count, 1)
    }

    func testDoesNotReannounceSameKilometer() {
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.prepareForNewSession(sessionID)

        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 1_050,
            activeElapsed: 500,
            state: .recording
        )
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 990,
            activeElapsed: 520,
            state: .recording
        )
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 1_080,
            activeElapsed: 540,
            state: .recording
        )

        XCTAssertEqual(controller.spokenPhrasesLog.count, 1)
    }

    func testPersistsAnnouncedKilometersAcrossRelaunch() {
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.prepareForNewSession(sessionID)
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 1_000,
            activeElapsed: 600,
            state: .recording
        )
        XCTAssertEqual(controller.spokenPhrasesLog.count, 1)

        // 앱 재실행 흉내: 디스크는 남기고 인메모리만 비운 뒤 같은 세션을 다시 bind.
        controller.resetInMemoryPreservingDiskForTests()
        controller.bindSession(
            sessionID,
            seedFromDistanceMeters: 1_100,
            seedActiveElapsed: 700
        )
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 1_100,
            activeElapsed: 700,
            state: .recording
        )
        // 디스크의 announced {1} 복구 → 재안내 없음
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)
    }

    func testLateBindSeedsPastKilometersWithoutSpeaking() {
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.bindSession(
            sessionID,
            seedFromDistanceMeters: 2_400,
            seedActiveElapsed: 1_800
        )
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 2_400,
            activeElapsed: 1_800,
            state: .recording
        )
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)

        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 3_000,
            activeElapsed: 2_400,
            state: .recording
        )
        XCTAssertEqual(
            controller.spokenPhrasesLog,
            ["3킬로미터 지점입니다. 이번 구간 10분, 총 산행 시간 40분입니다."]
        )
    }

    func testToggleOffSuppressesSpeech() {
        KmVoiceGuidancePreferences.isEnabled = false
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.prepareForNewSession(sessionID)
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 1_000,
            activeElapsed: 400,
            state: .recording
        )
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)
    }

    func testPreferencesDefaultOn() {
        let key = "sansan.kmVoiceGuidance.isEnabled"
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(KmVoiceGuidancePreferences.isEnabled)
    }
}

#endif
