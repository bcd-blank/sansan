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
            state: .recording,
            shouldSpeak: true
        )
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 2_000,
            activeElapsed: 1_500,
            state: .recording,
            shouldSpeak: true
        )
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 3_050,
            activeElapsed: 2_100,
            state: .recording,
            shouldSpeak: true
        )

        XCTAssertEqual(
            controller.spokenPhrasesLog,
            [
                "1킬로미터 지점입니다. 이번 구간 12분 0초, 총 산행 시간 12분 0초입니다.",
                "2킬로미터 지점입니다. 이번 구간 13분 0초, 총 산행 시간 25분 0초입니다.",
                "3킬로미터 지점입니다. 이번 구간 10분 0초, 총 산행 시간 35분 0초입니다.",
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
        ,
            shouldSpeak: true
        )
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)

        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 1_200,
            activeElapsed: 600,
            state: .recording
        ,
            shouldSpeak: true
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
        ,
            shouldSpeak: true
        )
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 990,
            activeElapsed: 520,
            state: .recording
        ,
            shouldSpeak: true
        )
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 1_080,
            activeElapsed: 540,
            state: .recording
        ,
            shouldSpeak: true
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
        ,
            shouldSpeak: true
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
        ,
            shouldSpeak: true
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
        ,
            shouldSpeak: true
        )
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)

        // 2.4km/30분 시드 → 2km 경계 근사 25분. 3km/40분이면 구간 15분(결합 시각 10분이 아님).
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 3_000,
            activeElapsed: 2_400,
            state: .recording
        ,
            shouldSpeak: true
        )
        XCTAssertEqual(
            controller.spokenPhrasesLog,
            ["3킬로미터 지점입니다. 이번 구간 15분 0초, 총 산행 시간 40분 0초입니다."]
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
        ,
            shouldSpeak: true
        )
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)
    }

    /// B04 — 900→2200m 한 갱신: 균등 분배, 두 번째 구간 0초 없음(Android와 동일).
    func testMultiKilometerCatchUpSplitsSegmentsEvenly() {
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.prepareForNewSession(sessionID)

        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 900,
            activeElapsed: 500,
            state: .recording
        ,
            shouldSpeak: true
        )
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)

        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 2_200,
            activeElapsed: 1_200,
            state: .recording
        ,
            shouldSpeak: true
        )
        XCTAssertEqual(
            controller.spokenPhrasesLog,
            [
                "1킬로미터 지점입니다. 이번 구간 10분 0초, 총 산행 시간 10분 0초입니다.",
                "2킬로미터 지점입니다. 이번 구간 10분 0초, 총 산행 시간 20분 0초입니다.",
            ]
        )
    }

    /// B05 — 세션 결합 후 OFF로 지나친 km는 ON해도 소급 발화하지 않습니다(처음부터 OFF와 동일).
    func testToggleOffDuringSessionSeedsWithoutCatchUpSpeech() {
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.prepareForNewSession(sessionID)

        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 1_000,
            activeElapsed: 600,
            state: .recording
        ,
            shouldSpeak: true
        )
        XCTAssertEqual(controller.spokenPhrasesLog.count, 1)

        KmVoiceGuidancePreferences.isEnabled = false
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 2_200,
            activeElapsed: 1_200,
            state: .recording
        ,
            shouldSpeak: true
        )
        XCTAssertEqual(controller.spokenPhrasesLog.count, 1)

        KmVoiceGuidancePreferences.isEnabled = true
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 2_200,
            activeElapsed: 1_250,
            state: .recording
        ,
            shouldSpeak: true
        )
        XCTAssertEqual(controller.spokenPhrasesLog.count, 1, "OFF 동안 넘긴 2km는 소급 발화 없음")

        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 3_000,
            activeElapsed: 1_800,
            state: .recording
        ,
            shouldSpeak: true
        )
        XCTAssertEqual(controller.spokenPhrasesLog.count, 2)
        XCTAssertEqual(
            controller.spokenPhrasesLog.last,
            "3킬로미터 지점입니다. 이번 구간 10분 0초, 총 산행 시간 30분 0초입니다."
        )
    }

    /// B05 — 처음부터 OFF로 지나친 km도 ON 후 소급 없음.
    func testToggleOnAfterDisabledStartDoesNotSpeakPastKilometers() {
        KmVoiceGuidancePreferences.isEnabled = false
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.prepareForNewSession(sessionID)
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 1_200,
            activeElapsed: 700,
            state: .recording
        ,
            shouldSpeak: true
        )
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)

        KmVoiceGuidancePreferences.isEnabled = true
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 1_200,
            activeElapsed: 720,
            state: .recording
        ,
            shouldSpeak: true
        )
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)
    }


    func testNonOwnerDoesNotSpeakOrMarkAnnounced() {
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.prepareForNewSession(sessionID)
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 1_000,
            activeElapsed: 600,
            state: .recording,
            shouldSpeak: false
        )
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)
        XCTAssertEqual(controller.currentAnnouncedState()?.announcedKilometers ?? [], [])

        controller.mergeRemoteAnnouncedState(
            KmVoiceAnnouncedState(
                sessionID: sessionID,
                announcedKilometers: [1],
                elapsedAtAnnouncedKilometers: ["1": 600]
            )
        )
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 1_050,
            activeElapsed: 620,
            state: .recording,
            shouldSpeak: true
        )
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)
    }

    func testHandoffPhoneSpeaksAfterWatchAnnouncedMerge() {
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.prepareForNewSession(sessionID)
        controller.mergeRemoteAnnouncedState(
            KmVoiceAnnouncedState(
                sessionID: sessionID,
                announcedKilometers: [1],
                elapsedAtAnnouncedKilometers: ["1": 700]
            )
        )
        controller.evaluate(
            sessionID: sessionID,
            distanceMeters: 2_000,
            activeElapsed: 1_400,
            state: .recording,
            shouldSpeak: true
        )
        XCTAssertEqual(controller.spokenPhrasesLog.count, 1)
        XCTAssertTrue(controller.spokenPhrasesLog[0].hasPrefix("2킬로미터"))
    }

    func testPreferencesDefaultOn() {
        let key = "sansan.kmVoiceGuidance.isEnabled"
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertTrue(KmVoiceGuidancePreferences.isEnabled)
    }

    func testAnnounceRecordingStartWhenEnabledAndOwner() {
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.prepareForNewSession(sessionID)

        controller.announceRecordingStart(shouldSpeak: true)
        XCTAssertEqual(
            controller.spokenPhrasesLog,
            ["산산 기록을 시작합니다."]
        )
        XCTAssertEqual(controller.currentAnnouncedState()?.didAnnounceStart, true)

        controller.announceRecordingStart(shouldSpeak: true)
        XCTAssertEqual(controller.spokenPhrasesLog.count, 1, "시작 안내는 세션당 1회")
    }

    func testAnnounceRecordingStartSuppressedWhenToggleOff() {
        KmVoiceGuidancePreferences.isEnabled = false
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.prepareForNewSession(sessionID)

        controller.announceRecordingStart(shouldSpeak: true)
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)
        XCTAssertEqual(controller.currentAnnouncedState()?.didAnnounceStart, true)

        KmVoiceGuidancePreferences.isEnabled = true
        controller.announceRecordingStart(shouldSpeak: true)
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty, "OFF로 시작했으면 중도 ON해도 시작 안내 없음")
    }

    func testAnnounceRecordingStartWaitsWhenNonOwner() {
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.prepareForNewSession(sessionID)

        controller.announceRecordingStart(shouldSpeak: false)
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)
        XCTAssertEqual(controller.currentAnnouncedState()?.didAnnounceStart, false)

        controller.mergeRemoteAnnouncedState(
            KmVoiceAnnouncedState(
                sessionID: sessionID,
                announcedKilometers: [],
                elapsedAtAnnouncedKilometers: [:],
                didAnnounceStart: true
            )
        )
        controller.announceRecordingStart(shouldSpeak: true)
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)
        XCTAssertEqual(controller.currentAnnouncedState()?.didAnnounceStart, true)
    }

    func testAnnounceRecordingEndIncludesDistanceAndTime() {
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.prepareForNewSession(sessionID)

        controller.announceRecordingEnd(
            distanceMeters: 2_350,
            activeElapsed: 12 * 60 + 34,
            shouldSpeak: true
        )
        XCTAssertEqual(
            controller.spokenPhrasesLog,
            ["산산 기록을 종료합니다. 총 거리 2.35킬로미터, 시간 12분 34초입니다."]
        )
        XCTAssertEqual(controller.currentAnnouncedState()?.didAnnounceEnd, true)

        controller.announceRecordingEnd(
            distanceMeters: 3_000,
            activeElapsed: 20 * 60,
            shouldSpeak: true
        )
        XCTAssertEqual(controller.spokenPhrasesLog.count, 1, "종료 안내는 세션당 1회")
    }

    func testAnnounceRecordingEndSuppressedWhenToggleOff() {
        KmVoiceGuidancePreferences.isEnabled = false
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.prepareForNewSession(sessionID)

        controller.announceRecordingEnd(
            distanceMeters: 1_000,
            activeElapsed: 600,
            shouldSpeak: true
        )
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)
        XCTAssertEqual(controller.currentAnnouncedState()?.didAnnounceEnd, true)
    }

    func testAnnounceRecordingEndWaitsWhenNonOwnerThenMerges() {
        let sessionID = UUID()
        let controller = KmVoiceGuidanceController.shared
        controller.prepareForNewSession(sessionID)

        controller.announceRecordingEnd(
            distanceMeters: 1_500,
            activeElapsed: 900,
            shouldSpeak: false
        )
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)
        XCTAssertEqual(controller.currentAnnouncedState()?.didAnnounceEnd, false)

        controller.mergeRemoteAnnouncedState(
            KmVoiceAnnouncedState(
                sessionID: sessionID,
                announcedKilometers: [],
                elapsedAtAnnouncedKilometers: [:],
                didAnnounceEnd: true
            )
        )
        controller.announceRecordingEnd(
            distanceMeters: 1_500,
            activeElapsed: 900,
            shouldSpeak: true
        )
        XCTAssertTrue(controller.spokenPhrasesLog.isEmpty)
    }
}

#endif
