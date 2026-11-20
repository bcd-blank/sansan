//
//  KmVoiceGuidancePhraseBuilderTests.swift
//  sansanTests
//

import XCTest
@testable import sansan

final class KmVoiceGuidancePhraseBuilderTests: XCTestCase {
    func testPhraseIncludesMinutesAndSeconds() {
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.phrase(
                kilometers: 2,
                segmentSeconds: 24 * 60,
                totalSeconds: 42 * 60
            ),
            "2킬로미터 지점입니다. 이번 구간 24분 0초, 총 산행 시간 42분 0초입니다."
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.phrase(
                kilometers: 3,
                segmentSeconds: 23 * 60,
                totalSeconds: 3_912
            ),
            "3킬로미터 지점입니다. 이번 구간 23분 0초, 총 산행 시간 1시간 5분 12초입니다."
        )
    }

    func testUnderOneMinuteUsesSeconds() {
        XCTAssertEqual(KmVoiceGuidancePhraseBuilder.formatDuration(40), "40초")
        XCTAssertEqual(KmVoiceGuidancePhraseBuilder.formatDuration(40.4), "40초")
        XCTAssertEqual(KmVoiceGuidancePhraseBuilder.formatDuration(40.6), "41초")
    }

    func testMinutesIncludeSeconds() {
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatDuration(12 * 60 + 34),
            "12분 34초"
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatDuration(14 * 60 + 30),
            "14분 30초"
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatDuration(14 * 60),
            "14분 0초"
        )
    }

    func testExactHour() {
        XCTAssertEqual(KmVoiceGuidancePhraseBuilder.formatDuration(3_600), "1시간")
        XCTAssertEqual(KmVoiceGuidancePhraseBuilder.formatDuration(7_200), "2시간")
    }

    func testHourMinutesAndSeconds() {
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatDuration(3_912),
            "1시간 5분 12초"
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatDuration(3_600 + 5),
            "1시간 0분 5초"
        )
    }

    func testRecordingStartAndEndPhrases() {
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.recordingStartPhrase,
            "산산 기록을 시작합니다."
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.recordingEndPhrase(
                distanceMeters: 1_250,
                totalSeconds: 12 * 60 + 34
            ),
            "산산 기록을 종료합니다. 총 거리 1.25킬로미터, 시간 12분 34초입니다."
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.recordingEndPhrase(
                distanceMeters: 850,
                totalSeconds: 3_912
            ),
            "산산 기록을 종료합니다. 총 거리 850미터, 시간 1시간 5분 12초입니다."
        )
    }

    func testFormatDistance() {
        XCTAssertEqual(KmVoiceGuidancePhraseBuilder.formatDistance(0), "0미터")
        XCTAssertEqual(KmVoiceGuidancePhraseBuilder.formatDistance(999), "999미터")
        XCTAssertEqual(KmVoiceGuidancePhraseBuilder.formatDistance(1_000), "1킬로미터")
        XCTAssertEqual(KmVoiceGuidancePhraseBuilder.formatDistance(2_350), "2.35킬로미터")
    }

    func testNewlyCrossedKilometersSkipsAlreadyAnnounced() {
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.newlyCrossedKilometers(
                distanceMeters: 2_050,
                alreadyAnnounced: [1]
            ),
            [2]
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.newlyCrossedKilometers(
                distanceMeters: 999,
                alreadyAnnounced: []
            ),
            []
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.newlyCrossedKilometers(
                distanceMeters: 3_100,
                alreadyAnnounced: []
            ),
            [1, 2, 3]
        )
    }

    func testSegmentSecondsUsesPreviousKmElapsed() {
        let elapsedAt: [Int: TimeInterval] = [1: 600, 2: 1_320]
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.segmentSeconds(
                for: 1,
                currentActiveElapsed: 600,
                elapsedAtAnnouncedKilometers: [:]
            ),
            600,
            accuracy: 0.001
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.segmentSeconds(
                for: 3,
                currentActiveElapsed: 2_000,
                elapsedAtAnnouncedKilometers: elapsedAt
            ),
            680,
            accuracy: 0.001
        )
    }

    func testOneToThreeKilometerExamples() {
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.phrase(
                kilometers: 1,
                segmentSeconds: 754,
                totalSeconds: 754
            ),
            "1킬로미터 지점입니다. 이번 구간 12분 34초, 총 산행 시간 12분 34초입니다."
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.phrase(
                kilometers: 2,
                segmentSeconds: 780,
                totalSeconds: 1_500
            ),
            "2킬로미터 지점입니다. 이번 구간 13분 0초, 총 산행 시간 25분 0초입니다."
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.phrase(
                kilometers: 3,
                segmentSeconds: 600,
                totalSeconds: 2_100
            ),
            "3킬로미터 지점입니다. 이번 구간 10분 0초, 총 산행 시간 35분 0초입니다."
        )
    }

    func testSecondsInPhrase() {
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.phrase(
                kilometers: 1,
                segmentSeconds: 40,
                totalSeconds: 40
            ),
            "1킬로미터 지점입니다. 이번 구간 40초, 총 산행 시간 40초입니다."
        )
    }

    func testPlanCatchUpCrossingsSplitsEvenlyLikeAndroid() {
        let plans = KmVoiceGuidancePhraseBuilder.planCatchUpCrossings(
            pendingKilometers: [1, 2, 3],
            baselineElapsed: 0,
            currentActiveElapsed: 900
        )
        XCTAssertEqual(plans.count, 3)
        XCTAssertEqual(plans[0].segmentSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(plans[0].totalSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(plans[1].segmentSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(plans[1].totalSeconds, 600, accuracy: 0.001)
        XCTAssertEqual(plans[2].segmentSeconds, 300, accuracy: 0.001)
        XCTAssertEqual(plans[2].totalSeconds, 900, accuracy: 0.001)
        XCTAssertFalse(plans.contains { $0.segmentSeconds == 0 })
    }

    func testSeedElapsedByDistanceApproximatesKmBoundaries() {
        let seeded = KmVoiceGuidancePhraseBuilder.seedElapsedByDistance(
            crossedKilometers: 2,
            distanceMeters: 2_400,
            activeElapsed: 1_800
        )
        XCTAssertEqual(seeded[1] ?? -1, 1_800 * (1_000 / 2_400), accuracy: 0.001)
        XCTAssertEqual(seeded[2] ?? -1, 1_800 * (2_000 / 2_400), accuracy: 0.001)
    }
}
