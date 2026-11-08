//
//  KmVoiceGuidancePhraseBuilderTests.swift
//  sansanTests
//

import XCTest
@testable import sansan

final class KmVoiceGuidancePhraseBuilderTests: XCTestCase {
    func testPhraseIncludesSegmentAndTotal() {
        let phrase = KmVoiceGuidancePhraseBuilder.phrase(
            kilometers: 2,
            segmentSeconds: 18 * 60,
            totalSeconds: 3_900
        )
        XCTAssertEqual(
            phrase,
            "2킬로 지점입니다. 이번 1킬로는 18분, 전체 시간은 1시간 5분입니다."
        )
    }

    func testUnderOneMinuteUsesSeconds() {
        XCTAssertEqual(KmVoiceGuidancePhraseBuilder.formatDuration(40), "40초")
        XCTAssertEqual(KmVoiceGuidancePhraseBuilder.formatDuration(40.4), "40초")
        XCTAssertEqual(KmVoiceGuidancePhraseBuilder.formatDuration(40.6), "41초")
    }

    func testMinutesAreRounded() {
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatDuration(14 * 60 + 30),
            "15분"
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatDuration(14 * 60 + 29),
            "14분"
        )
    }

    func testExactHour() {
        XCTAssertEqual(KmVoiceGuidancePhraseBuilder.formatDuration(3_600), "1시간")
        XCTAssertEqual(KmVoiceGuidancePhraseBuilder.formatDuration(7_200), "2시간")
    }

    func testHourAndMinutes() {
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatDuration(3_900),
            "1시간 5분"
        )
    }

    func testNearHourRoundsToExactHour() {
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatDuration(59 * 60 + 30),
            "1시간"
        )
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
        // 1km: segment 12분 = total 12분
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.phrase(
                kilometers: 1,
                segmentSeconds: 720,
                totalSeconds: 720
            ),
            "1킬로 지점입니다. 이번 1킬로는 12분, 전체 시간은 12분입니다."
        )
        // 2km: segment 13분, total 25분
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.phrase(
                kilometers: 2,
                segmentSeconds: 780,
                totalSeconds: 1_500
            ),
            "2킬로 지점입니다. 이번 1킬로는 13분, 전체 시간은 25분입니다."
        )
        // 3km: segment 10분, total 35분
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.phrase(
                kilometers: 3,
                segmentSeconds: 600,
                totalSeconds: 2_100
            ),
            "3킬로 지점입니다. 이번 1킬로는 10분, 전체 시간은 35분입니다."
        )
    }

    func testSecondsAndHourComboInPhrase() {
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.phrase(
                kilometers: 1,
                segmentSeconds: 40,
                totalSeconds: 40
            ),
            "1킬로 지점입니다. 이번 1킬로는 40초, 전체 시간은 40초입니다."
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.phrase(
                kilometers: 3,
                segmentSeconds: 18 * 60,
                totalSeconds: 3_900
            ),
            "3킬로 지점입니다. 이번 1킬로는 18분, 전체 시간은 1시간 5분입니다."
        )
    }
}
