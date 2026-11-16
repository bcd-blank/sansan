//
//  KMSCCourseCatalogTests.swift
//  sansanTests
//

import XCTest
@testable import sansan

final class KMSCCourseCatalogTests: XCTestCase {
    func testDecodeCatalogJSON() throws {
        let json = """
        {
          "version": 1,
          "courses": [
            {
              "id": "100대명산/월악산/월악산_0000000001.gpx",
              "category": "100대명산",
              "groupName": "월악산",
              "title": "월악산 1",
              "relativePath": "100대명산/월악산/월악산_0000000001.gpx"
            },
            {
              "id": "9정맥 종주코스/한남정맥/한남정맥_0000000001.gpx",
              "category": "9정맥 종주코스",
              "groupName": "한남정맥",
              "title": "한남정맥 1",
              "relativePath": "9정맥 종주코스/한남정맥/한남정맥_0000000001.gpx"
            }
          ]
        }
        """
        let courses = try KMSCCourseCatalog.decodeCatalog(from: Data(json.utf8))
        XCTAssertEqual(courses.map(\.category), ["100대명산", "9정맥 종주코스"])
        XCTAssertEqual(courses.first?.title, "월악산 1")
        XCTAssertEqual(courses.first?.id, courses.first?.relativePath)
    }

    func testBundledCatalogLoadsWithoutWalkingGPX() {
        XCTAssertGreaterThanOrEqual(KMSCCourseCatalog.allCourses.count, 600)
        XCTAssertTrue(KMSCCourseCatalog.categories.contains(where: { $0.contains("100") }))
    }

    func testRemoteURLEncodesKoreanPathComponents() throws {
        let base = try XCTUnwrap(URL(string: "https://example.com/KMSC"))
        let url = KMSCCourseRemote.fileURL(
            baseURL: base,
            relativePath: "100대명산/월악산/월악산_0000000001.gpx"
        )
        XCTAssertEqual(url.pathExtension, "gpx")
        XCTAssertTrue(url.absoluteString.contains("100"))
        XCTAssertFalse(url.absoluteString.contains(" "))
    }
}
