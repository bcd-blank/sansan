//
//  ElevationChartYAxisSpecTests.swift
//  sansanTests
//

import XCTest
@testable import sansan

final class ElevationChartYAxisSpecTests: XCTestCase {
    /// 1000m를 넘어도 Y축이 0…10000으로 벌어지지 않아야 합니다.
    func testDomainStaysNearDataWhenAltitudeExceeds1000() {
        let spec = ElevationChartYAxisSpec.fitting(minAltitude: 888, maxAltitude: 1_583)

        XCTAssertLessThan(spec.domain.upperBound, 4_000)
        XCTAssertGreaterThan(spec.domain.lowerBound, 400)
        XCTAssertGreaterThanOrEqual(spec.domain.lowerBound, 0)
        XCTAssertTrue(spec.domain.contains(888))
        XCTAssertTrue(spec.domain.contains(1_583))
        XCTAssertFalse(spec.ticks.contains(10_000))
        XCTAssertLessThanOrEqual(spec.ticks.count, 8)
    }

    func testExactly1000DoesNotJumpTo10000() {
        let spec = ElevationChartYAxisSpec.fitting(minAltitude: 920, maxAltitude: 1_001)

        XCTAssertLessThan(spec.domain.upperBound, 3_000)
        XCTAssertFalse(spec.ticks.contains(where: { $0 >= 10_000 }))
    }

    func testNiceStepDoesNotCeilLog10ToNextPowerOfTen() {
        XCTAssertEqual(ElevationChartYAxisSpec.niceStep(150), 200)
        XCTAssertEqual(ElevationChartYAxisSpec.niceStep(215), 500)
        XCTAssertEqual(ElevationChartYAxisSpec.niceStep(1_001), 2_000)
        XCTAssertNotEqual(ElevationChartYAxisSpec.niceStep(1_001), 10_000)
    }

    func testLowElevationStillHasReadableTicks() {
        let spec = ElevationChartYAxisSpec.fitting(minAltitude: 12, maxAltitude: 48)
        XCTAssertEqual(spec.domain.lowerBound, 0, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(spec.domain.upperBound, 48)
        XCTAssertGreaterThanOrEqual(spec.ticks.count, 3)
    }
}
