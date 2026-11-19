//
//  AppUpdateCheckerTests.swift
//  sansanTests
//

#if os(iOS)

import XCTest
@testable import sansan

final class AppUpdateCheckerTests: XCTestCase {
    func testCompareVersionsEqualAndUnevenDigits() {
        XCTAssertEqual(AppUpdateChecker.compareVersions("1.0.6", "1.0.6"), .orderedSame)
        XCTAssertEqual(AppUpdateChecker.compareVersions("1.0.5", "1.0.6"), .orderedAscending)
        XCTAssertEqual(AppUpdateChecker.compareVersions("1.0.7", "1.0.6"), .orderedDescending)
        XCTAssertEqual(AppUpdateChecker.compareVersions("1.0.10", "1.0.9"), .orderedDescending)
        XCTAssertEqual(AppUpdateChecker.compareVersions("1.0", "1.0.0"), .orderedSame)
        XCTAssertEqual(AppUpdateChecker.compareVersions("1.0.0", "1.0"), .orderedSame)
        XCTAssertNil(AppUpdateChecker.compareVersions("1.0.x", "1.0.6"))
        XCTAssertNil(AppUpdateChecker.compareVersions("1.0.6", "abc"))
    }

    func testParseLookupSuccessAndFailures() throws {
        let okJSON = """
        {"resultCount":1,"results":[{"version":"1.0.7","trackViewUrl":"https://apps.apple.com/kr/app/id6800198509","minimumOsVersion":"26.5"}]}
        """.data(using: .utf8)!
        let parsed = try XCTUnwrap(AppUpdateChecker.parseLookupResponse(okJSON))
        XCTAssertEqual(parsed.version, "1.0.7")
        XCTAssertEqual(parsed.trackViewURL?.absoluteString, "https://apps.apple.com/kr/app/id6800198509")
        XCTAssertEqual(parsed.minimumOSVersion, "26.5")

        let empty = #"{"resultCount":0,"results":[]}"#.data(using: .utf8)!
        XCTAssertNil(AppUpdateChecker.parseLookupResponse(empty))

        let missingVersion = #"{"resultCount":1,"results":[{"trackViewUrl":"https://apps.apple.com/kr/app/id6800198509"}]}"#.data(using: .utf8)!
        XCTAssertNil(AppUpdateChecker.parseLookupResponse(missingVersion))
    }

    func testStatusAvailableUpToDateAndMinimumOS() throws {
        let storeURL = try XCTUnwrap(URL(string: "https://apps.apple.com/kr/app/id6800198509"))

        XCTAssertEqual(
            AppUpdateChecker.status(
                storeVersion: "1.0.5",
                storeURL: storeURL,
                minimumOSVersion: "26.5",
                localVersion: "1.0.6",
                systemVersion: "26.5"
            ),
            .upToDate
        )

        XCTAssertEqual(
            AppUpdateChecker.status(
                storeVersion: "1.0.7",
                storeURL: storeURL,
                minimumOSVersion: "26.5",
                localVersion: "1.0.6",
                systemVersion: "26.5"
            ),
            .available(version: "1.0.7", url: storeURL)
        )

        // 기기 OS가 요구보다 낮으면 안내하지 않음.
        XCTAssertEqual(
            AppUpdateChecker.status(
                storeVersion: "1.0.7",
                storeURL: storeURL,
                minimumOSVersion: "99.0",
                localVersion: "1.0.6",
                systemVersion: "26.5"
            ),
            .upToDate
        )

        XCTAssertNil(
            AppUpdateChecker.status(
                storeVersion: "1.0.x",
                storeURL: storeURL,
                minimumOSVersion: nil,
                localVersion: "1.0.6",
                systemVersion: "26.5"
            )
        )
    }

    func testCacheFreshnessAndRoundTrip() {
        let suiteName = "AppUpdateCheckerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let url = URL(string: "https://apps.apple.com/kr/app/id6800198509")!
        let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)
        AppUpdateChecker.saveCache(
            storeVersion: "1.0.5",
            storeURL: url,
            checkedAt: checkedAt,
            defaults: defaults
        )

        let loaded = AppUpdateChecker.loadCache(now: checkedAt, defaults: defaults)
        XCTAssertEqual(loaded?.storeVersion, "1.0.5")
        XCTAssertEqual(loaded?.storeURL, url)
        XCTAssertEqual(loaded?.checkedAt.timeIntervalSince1970, checkedAt.timeIntervalSince1970)

        XCTAssertTrue(
            AppUpdateChecker.isCacheFresh(
                loaded!,
                now: checkedAt.addingTimeInterval(5 * 60 * 60)
            )
        )
        XCTAssertFalse(
            AppUpdateChecker.isCacheFresh(
                loaded!,
                now: checkedAt.addingTimeInterval(6 * 60 * 60 + 1)
            )
        )
    }

    func testResolveStatusUsesFallbackURLWhenTrackViewMissing() {
        let lookup = AppUpdateChecker.LookupResult(
            version: "1.0.7",
            trackViewURL: nil,
            minimumOSVersion: nil
        )
        let status = AppUpdateChecker.resolveStatus(
            lookup: lookup,
            localVersion: "1.0.6",
            systemVersion: "26.5"
        )
        XCTAssertEqual(
            status,
            .available(version: "1.0.7", url: AppUpdateChecker.fallbackStoreURL)
        )
    }
}

#endif
