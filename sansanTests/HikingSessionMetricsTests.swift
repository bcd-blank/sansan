//
//  HikingSessionMetricsTests.swift
//  sansanTests
//

import CoreLocation
import XCTest
@testable import sansan

final class HikingSessionMetricsTests: XCTestCase {
    /// 평지 +2m 스파이크는 등반 속도 한도(0.6m/s)까지만 반영됩니다.
    func testStoredAltitudeClampsFlatGroundSpike() {
        let previous = 100.0
        let proposed = 102.0
        let filtered = HikingSessionMetrics.storedAltitude(
            proposed: proposed,
            previousAltitude: previous,
            horizontalMeters: 4,
            elapsedSeconds: 1
        )
        XCTAssertEqual(
            filtered,
            previous + HikingSessionMetrics.maximumVerticalClimbRateMetersPerSecond,
            accuracy: 0.001
        )
    }

    /// 가파른 계단(수직 0.4m/s, 수평 1m/s)을 꾸준히 오를 때 고도가 멈추지 않고 따라가야 합니다.
    func testStoredAltitudeTracksSustainedSteepClimb() {
        var stored = 100.0
        for step in 1...60 {
            let actual = 100.0 + 0.4 * Double(step)
            stored = HikingSessionMetrics.storedAltitude(
                proposed: actual,
                previousAltitude: stored,
                horizontalMeters: 1.0,
                elapsedSeconds: 1
            )
        }
        XCTAssertEqual(stored, 124.0, accuracy: 2.0)
    }

    func testStoredAltitudeAcceptsGradualClimb() {
        let previous = 100.0
        let proposed = 100.5
        let filtered = HikingSessionMetrics.storedAltitude(
            proposed: proposed,
            previousAltitude: previous,
            horizontalMeters: 5,
            elapsedSeconds: 1
        )
        XCTAssertEqual(filtered, proposed, accuracy: 0.001)
    }

    /// 1초당 약 1.2m 저속 보행 — 연속 구간이 2m 미만이어도 거리가 유실되면 안 됩니다.
    func testHorizontalDistancePreservesSlowWalk() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let stepDegrees = 1.2 / 111_320.0
        let points = (0..<100).map { index in
            HikingPoint(
                latitude: 37.5 + Double(index) * stepDegrees,
                longitude: 127.0,
                altitude: 100,
                timestamp: base.addingTimeInterval(Double(index))
            )
        }

        let distance = HikingSessionMetrics.horizontalDistance(from: points)
        XCTAssertGreaterThan(distance, 110)
        XCTAssertLessThan(distance, 130)
    }

    /// 실내 다중경로처럼 노이즈 반경(수평 정확도) 안에서 크게 튀는 포인트는 거리에 더하지 않습니다.
    func testHorizontalDistanceIgnoresIndoorMultipathJumps() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let jumpsMeters: [Double] = [0, 8, -12, 15, -7, 18, -10, 5, -16, 11]
        let points = jumpsMeters.enumerated().map { index, offset in
            HikingPoint(
                latitude: 37.5 + offset / 111_320.0,
                longitude: 127.0,
                altitude: 27,
                timestamp: base.addingTimeInterval(Double(index) * 9),
                horizontalAccuracy: 25
            )
        }

        XCTAssertEqual(HikingSessionMetrics.horizontalDistance(from: points), 0, accuracy: 0.001)
    }

    /// 야외 보행(정확도 5m)은 정확도 비례 임계값을 적용해도 거리가 보존되어야 합니다.
    func testHorizontalDistancePreservesWalkWithGoodAccuracy() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let stepDegrees = 1.2 / 111_320.0
        let points = (0..<100).map { index in
            HikingPoint(
                latitude: 37.5 + Double(index) * stepDegrees,
                longitude: 127.0,
                altitude: 100,
                timestamp: base.addingTimeInterval(Double(index)),
                horizontalAccuracy: 5
            )
        }

        let distance = HikingSessionMetrics.horizontalDistance(from: points)
        XCTAssertGreaterThan(distance, 110)
        XCTAssertLessThan(distance, 130)
    }

    /// 정지 상태에서 2m 미만으로 흔들리는 GPS 노이즈는 거리에 더하지 않습니다.
    func testHorizontalDistanceIgnoresStationaryJitter() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let jitterDegrees = 0.5 / 111_320.0
        let points = (0..<60).map { index in
            HikingPoint(
                latitude: 37.5 + (index.isMultiple(of: 2) ? jitterDegrees : -jitterDegrees),
                longitude: 127.0,
                altitude: 100,
                timestamp: base.addingTimeInterval(Double(index))
            )
        }

        XCTAssertEqual(HikingSessionMetrics.horizontalDistance(from: points), 0, accuracy: 0.001)
    }

    /// 잘린 스냅샷으로 먼저 저장된 세션과 전체 세션을 병합하면 포인트가 합집합이 되어야 합니다.
    func testMergingSameSessionUnionsPoints() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let allPoints = (0..<10).map { index in
            HikingPoint(
                latitude: 37.5 + Double(index) * 0.0001,
                longitude: 127.0,
                altitude: 100,
                timestamp: base.addingTimeInterval(Double(index))
            )
        }
        let sessionID = UUID()
        var partial = HikingSessionData(sessionID: sessionID)
        partial.points = Array(allPoints.suffix(3))
        partial.elapsedTime = 100
        var full = HikingSessionData(sessionID: sessionID)
        full.points = allPoints
        full.elapsedTime = 120

        let merged = partial.mergingSameSession(with: full)
        XCTAssertEqual(merged.points.count, allPoints.count)
        XCTAssertEqual(merged.points.map(\.id), allPoints.map(\.id))
        XCTAssertEqual(merged.elapsedTime, 120)
    }

    /// 완만한 오르막(초당 0.1m 상승)은 임계값 래칫 방식에서도 거의 전부 누적되어야 합니다.
    func testCumulativeGainTracksGradualClimb() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let stepDegrees = 1.2 / 111_320.0
        let points = (0..<300).map { index in
            HikingPoint(
                latitude: 37.5 + Double(index) * stepDegrees,
                longitude: 127.0,
                altitude: 100 + 0.1 * Double(index),
                timestamp: base.addingTimeInterval(Double(index))
            )
        }

        let gain = HikingSessionMetrics.cumulativeElevationGain(from: points)
        XCTAssertGreaterThan(gain, 25)
        XCTAssertLessThan(gain, 31)
    }

    func testCumulativeGainIgnoresFlatGroundNoise() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var points: [HikingPoint] = []

        for index in 0..<20 {
            let rawAltitude = index == 10 ? 102.0 : 100.0
            let storedAltitude: Double
            if let last = points.last {
                storedAltitude = HikingSessionMetrics.storedAltitude(
                    proposed: rawAltitude,
                    previousAltitude: last.altitude,
                    horizontalMeters: 1.1,
                    elapsedSeconds: 1
                )
            } else {
                storedAltitude = rawAltitude
            }

            points.append(
                HikingPoint(
                    latitude: 37.5 + Double(index) * 0.00001,
                    longitude: 127.0,
                    altitude: storedAltitude,
                    timestamp: base.addingTimeInterval(Double(index))
                )
            )
        }

        let gain = HikingSessionMetrics.cumulativeElevationGain(from: points)
        XCTAssertLessThan(gain, 0.5)
    }
}
