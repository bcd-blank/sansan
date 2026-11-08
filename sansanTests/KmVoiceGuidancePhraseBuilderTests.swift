//
//  KmVoiceGuidancePhraseBuilderTests.swift
//  sansanTests
//

import XCTest
@testable import sansan

final class KmVoiceGuidancePhraseBuilderTests: XCTestCase {
    func testPhraseUsesSegmentSecondsNotTotalElapsed() {
        let phrase = KmVoiceGuidancePhraseBuilder.phrase(kilometers: 2, segmentSeconds: 720)
        XCTAssertEqual(phrase, "2킬로 지점입니다. 걸린 시간은 12분입니다.")
    }

    func testUnderOneMinuteUsesSeconds() {
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatSegmentDuration(40),
            "40초입니다."
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatSegmentDuration(40.4),
            "40초입니다."
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatSegmentDuration(40.6),
            "41초입니다."
        )
    }

    func testMinutesAreRounded() {
        // 14분 30초 → 15분
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatSegmentDuration(14 * 60 + 30),
            "15분입니다."
        )
        // 14분 29초 → 14분
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatSegmentDuration(14 * 60 + 29),
            "14분입니다."
        )
    }

    func testExactHour() {
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatSegmentDuration(3_600),
            "1시간입니다."
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatSegmentDuration(7_200),
            "2시간입니다."
        )
    }

    func testHourAndMinutes() {
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatSegmentDuration(3_900),
            "1시간 5분입니다."
        )
    }

    func testNearHourRoundsToExactHour() {
        // 59분 30초 → 60분 → 1시간
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.formatSegmentDuration(59 * 60 + 30),
            "1시간입니다."
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

    func testFullPhraseExamples() {
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.phrase(kilometers: 1, segmentSeconds: 40),
            "1킬로 지점입니다. 걸린 시간은 40초입니다."
        )
        XCTAssertEqual(
            KmVoiceGuidancePhraseBuilder.phrase(kilometers: 3, segmentSeconds: 3_900),
            "3킬로 지점입니다. 걸린 시간은 1시간 5분입니다."
        )
    }
}
