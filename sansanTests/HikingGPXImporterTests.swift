//
//  HikingGPXImporterTests.swift
//  sansanTests
//

import XCTest
@testable import sansan

final class HikingGPXImporterTests: XCTestCase {
    private let validGPX = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="sansan-test">
      <metadata>
        <time>2024-06-01T10:00:00Z</time>
      </metadata>
      <trk>
        <name>Test Trail</name>
        <trkseg>
          <trkpt lat="37.5" lon="127.0">
            <ele>100</ele>
            <time>2024-06-01T10:00:00Z</time>
          </trkpt>
          <trkpt lat="37.501" lon="127.001">
            <ele>150</ele>
            <time>2024-06-01T10:30:00Z</time>
          </trkpt>
        </trkseg>
      </trk>
    </gpx>
    """

    func testParseValidTrack() throws {
        let data = Data(validGPX.utf8)
        let parsed = try HikingGPXImporter.parse(data: data, suggestedName: "fallback")

        XCTAssertEqual(parsed.displayName, "Test Trail")
        XCTAssertEqual(parsed.sessionData.points.count, 2)
        XCTAssertEqual(parsed.sessionData.points.first!.latitude, 37.5, accuracy: 0.0001)
        XCTAssertEqual(parsed.sessionData.points.last!.altitude, 150, accuracy: 0.1)
        XCTAssertEqual(parsed.sessionData.elapsedTime, 1_800, accuracy: 1)
        XCTAssertEqual(parsed.endedAt, parsed.sessionData.points.last!.timestamp)
    }

    func testParseRejectsSinglePoint() {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <trkseg>
              <trkpt lat="37.5" lon="127.0"/>
            </trkseg>
          </trk>
        </gpx>
        """
        XCTAssertThrowsError(try HikingGPXImporter.parse(data: Data(gpx.utf8), suggestedName: "x")) { error in
            guard case .insufficientPoints = error as? HikingGPXImporter.ImportError else {
                return XCTFail("Expected insufficientPoints, got \(error)")
            }
        }
    }

    func testParseRejectsInvalidXML() {
        let data = Data("<gpx><unclosed>".utf8)
        XCTAssertThrowsError(try HikingGPXImporter.parse(data: data, suggestedName: "x")) { error in
            guard case .invalidFormat = error as? HikingGPXImporter.ImportError else {
                return XCTFail("Expected invalidFormat, got \(error)")
            }
        }
    }
}
