//
//  HikingTrackPostProcessorTests.swift
//  sansanTests
//

import CoreLocation
import Foundation
import XCTest
@testable import sansan

final class HikingTrackPostProcessorTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let metersPerDegree = 111_320.0

    /// 1.2m/s 직선 보행은 점을 버리지 않습니다.
    func testKeepsSteadyWalk() {
        let points = stride(from: 0, through: 50, by: 1).map { index in
            point(north: 1.2 * Double(index), at: TimeInterval(index))
        }

        let kept = HikingTrackPostProcessor.removingOutliers(from: points)
        XCTAssertEqual(kept.count, points.count)
    }

    /// 4초에 100m(25m/s)는 그 시간에 사람이 낼 수 없으므로 제거합니다.
    /// 튄 점 다음의 정상 보행점은 직전 채택점 기준으로 다시 붙습니다.
    func testDropsTeleportFasterThanHumanSpeed() {
        let start = point(north: 0, at: 0)
        let before = point(north: 4, at: 4)
        let teleport = point(north: 100, at: 8)
        let resume = point(north: 8, at: 12)
        let keptIDs = Set(
            HikingTrackPostProcessor.removingOutliers(from: [start, before, teleport, resume]).map(\.id)
        )

        XCTAssertTrue(keptIDs.contains(start.id))
        XCTAssertTrue(keptIDs.contains(before.id))
        XCTAssertFalse(keptIDs.contains(teleport.id))
        XCTAssertTrue(keptIDs.contains(resume.id))
    }

    /// 보행 속도로도 몇 초 만에 옆으로 갔다가 돌아오면 전후 점으로 스파이크로 제거합니다.
    func testDropsShortLookaheadSpike() {
        let start = point(north: 0, at: 0)
        let spike = point(north: 2, east: 10, at: 5)
        let resume = point(north: 4, at: 10)

        let keptIDs = Set(
            HikingTrackPostProcessor.removingOutliers(from: [start, spike, resume]).map(\.id)
        )

        XCTAssertTrue(keptIDs.contains(start.id))
        XCTAssertFalse(keptIDs.contains(spike.id))
        XCTAssertTrue(keptIDs.contains(resume.id))
    }

    /// 20초+20초 헤어핀은 A→C가 스파이크 창보다 길어서 능선 꺾임으로 남깁니다.
    func testKeepsSlowHairpinSwitchback() {
        let start = point(north: 0, at: 0)
        let apex = point(north: 20, at: 20)
        let finish = point(north: 0, east: 5, at: 40)

        let keptIDs = Set(
            HikingTrackPostProcessor.removingOutliers(from: [start, apex, finish]).map(\.id)
        )

        XCTAssertEqual(keptIDs, [start.id, apex.id, finish.id])
    }

    /// 너무 빠른 점이 연속이어도 A–C로 지우지 않고, 굽은 구간의 꼭짓점을 남깁니다.
    func testClampsConsecutiveJumpsInsteadOfStraightChord() {
        let start = point(north: 0, at: 0)
        let northJump = point(north: 40, at: 4)
        let eastJump = point(north: 40, east: 40, at: 8)
        let resume = point(north: 40, east: 48, at: 24)

        let kept = HikingTrackPostProcessor.removingOutliers(
            from: [start, northJump, eastJump, resume]
        )

        XCTAssertGreaterThanOrEqual(kept.count, 3)
        XCTAssertEqual(kept.first?.id, start.id)
        XCTAssertEqual(kept.last?.id, resume.id)

        let northing = kept.map(\.northMeters)
        let easting = kept.map(\.eastMeters)
        XCTAssertGreaterThan(northing.max() ?? 0, 10, "북쪽으로 꺾인 꼭짓점이 남아야 합니다")
        XCTAssertGreaterThan(easting.max() ?? 0, 10, "동쪽으로 꺾인 꼭짓점이 남아야 합니다")

        let chordOnly = kept.count == 2
        XCTAssertFalse(chordOnly)
    }

    /// 먼 점프는 삭제하지 않고, 예측·관측 MAP 위치로 줄여 남깁니다.
    func testCorrectsFarJumpWithStatisticalEstimate() {
        let start = point(north: 0, at: 0)
        let jump = point(north: 80, at: 5)
        let resume = point(north: 90, at: 25)
        let kept = HikingTrackPostProcessor.removingOutliers(from: [start, jump, resume])

        XCTAssertEqual(kept.count, 3)
        XCTAssertEqual(kept[1].id, jump.id)
        let moved = kept[1].northMeters
        let maxReachable = HikingTrackPostProcessor.maxPlausibleSpeedMetersPerSecond * 5
        XCTAssertLessThan(moved, 40, "관측을 그대로 따라가면 안 됩니다")
        XCTAssertLessThanOrEqual(moved, maxReachable + 1.5)
        XCTAssertGreaterThan(moved, 0.5)
    }

    func testStatisticalCorrectionIsCloserToPredictionThanRawJump() {
        let start = point(north: 0, at: 0)
        let walking = point(north: 6, at: 5)
        let jump = point(north: 6, east: 80, at: 9)
        let corrected = HikingGPSStatisticalCorrection.correctedPoint(
            previous: walking,
            prior: start,
            candidate: jump,
            maxSpeedMetersPerSecond: 3.5
        )

        XCTAssertLessThan(abs(corrected.eastMeters), 25, "옆 튐을 GPS 방향으로 따라가면 안 됩니다")
        XCTAssertGreaterThan(corrected.northMeters, 4)
    }

    private func point(north: Double, east: Double = 0, at offset: TimeInterval) -> HikingPoint {
        HikingPoint(
            latitude: 37.5 + north / metersPerDegree,
            longitude: 127.0 + east / (metersPerDegree * cos(37.5 * .pi / 180)),
            altitude: 800,
            timestamp: base.addingTimeInterval(offset)
        )
    }
}

private extension HikingPoint {
    var northMeters: Double { (latitude - 37.5) * 111_320 }
    var eastMeters: Double {
        (longitude - 127.0) * 111_320 * cos(37.5 * .pi / 180)
    }
}
