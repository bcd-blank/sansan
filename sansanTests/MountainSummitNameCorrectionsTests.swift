//
//  MountainSummitNameCorrectionsTests.swift
//  sansanTests
//

import CoreLocation
import XCTest
@testable import sansan

final class MountainSummitNameCorrectionsTests: XCTestCase {
    func testMayusanInGapyeongDisplaysAsYumyeongsan() {
        let summit = MountainSummit(
            id: 5_388_363_536,
            name: "마유산",
            latitude: 37.5753362,
            longitude: 127.486706,
            elevationMeters: 864
        )

        XCTAssertEqual(summit.displayName, "유명산")
        XCTAssertEqual(
            MountainSummitNameCorrections.applyingPreferredName(to: summit).name,
            "유명산"
        )
    }

    func testRegionalAliasDoesNotApplyOutsideBounds() {
        let otherMayusan = MountainSummit(
            id: 99,
            name: "마유산",
            latitude: 36.0,
            longitude: 128.0,
            elevationMeters: 500
        )

        XCTAssertEqual(otherMayusan.displayName, "마유산")
    }

    func testSouthernYumyeongsanEntryIsUnchanged() {
        let southern = MountainSummit(
            id: 3_283_340_608,
            name: "유명산",
            latitude: 34.2044404,
            longitude: 129.2650978,
            elevationMeters: 558
        )

        XCTAssertEqual(southern.displayName, "유명산")
    }
}
