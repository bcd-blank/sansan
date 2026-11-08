//
//  HikingDurationFormattingTests.swift
//  sansanTests
//

import XCTest
@testable import sansan

final class HikingDurationFormattingTests: XCTestCase {
    func testStandardStyleUnderOneHour() {
        XCTAssertEqual(
            HikingDurationFormatting.displayString(elapsedSeconds: 2_730, style: .standard),
            "45:30"
        )
    }

    func testStandardStyleWithHours() {
        XCTAssertEqual(
            HikingDurationFormatting.displayString(elapsedSeconds: 3_930, style: .standard),
            "1:05:30"
        )
    }

    func testCompactStyleWithHours() {
        XCTAssertEqual(
            HikingDurationFormatting.displayString(elapsedSeconds: 12_300, style: .compact),
            "3h 25m"
        )
    }

    func testCompactStyleUnderOneHour() {
        XCTAssertEqual(
            HikingDurationFormatting.displayString(elapsedSeconds: 2_730, style: .compact),
            "45:30"
        )
    }

    func testNegativeElapsedClampsToZero() {
        XCTAssertEqual(
            HikingDurationFormatting.displayString(elapsedSeconds: -12, style: .standard),
            "00:00"
        )
    }
}
