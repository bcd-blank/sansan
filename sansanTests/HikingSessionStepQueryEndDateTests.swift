//
//  HikingSessionStepQueryEndDateTests.swift
//  sansanTests
//
//  B03 — 걸음 조회 끝은 벽시계 종료(lastUpdated)이며 effectiveEndedAt(활동 시간)이 아닙니다.
//

import XCTest
@testable import sansan

final class HikingSessionStepQueryEndDateTests: XCTestCase {
    func testStepQueryEndUsesWallClockWhenPauseShortensEffectiveEndedAt() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let pauseSeconds: TimeInterval = 120
        let activeElapsed: TimeInterval = 600
        let wallEnd = start.addingTimeInterval(activeElapsed + pauseSeconds)

        var session = HikingSessionData(
            sessionID: UUID(),
            state: .idle,
            startedAt: start,
            elapsedTime: activeElapsed,
            lastUpdated: wallEnd
        )
        session.points = [
            HikingPoint(
                latitude: 37.5,
                longitude: 127.0,
                altitude: 100,
                timestamp: start
            ),
            HikingPoint(
                latitude: 37.501,
                longitude: 127.0,
                altitude: 110,
                timestamp: start.addingTimeInterval(activeElapsed + 30)
            ),
        ]

        let effectiveEnd = session.effectiveEndedAt
        let queryEnd = session.stepCountQueryEndDate

        XCTAssertEqual(
            effectiveEnd.timeIntervalSince(start),
            activeElapsed,
            accuracy: 0.001,
            "표시용 종료는 활동 시간 기준(시작+600초)"
        )
        XCTAssertEqual(
            queryEnd.timeIntervalSince(start),
            activeElapsed + pauseSeconds,
            accuracy: 0.001,
            "걸음 조회 끝은 벽시계 lastUpdated(시작+720초)"
        )
        XCTAssertEqual(
            queryEnd.timeIntervalSince(effectiveEnd),
            pauseSeconds,
            accuracy: 0.001,
            "일시정지 120초만큼 조회 구간이 effectiveEndedAt보다 길어야 합니다"
        )
        XCTAssertEqual(queryEnd, wallEnd)
    }

    func testStepQueryEndPrefersLaterPointTimestamp() {
        let start = Date(timeIntervalSince1970: 1_700_100_000)
        let lastUpdated = start.addingTimeInterval(500)
        let lastPointAt = start.addingTimeInterval(560)
        var session = HikingSessionData(
            sessionID: UUID(),
            state: .idle,
            startedAt: start,
            elapsedTime: 500,
            lastUpdated: lastUpdated
        )
        session.points = [
            HikingPoint(
                latitude: 37.5,
                longitude: 127.0,
                altitude: 100,
                timestamp: lastPointAt
            ),
        ]

        XCTAssertEqual(session.stepCountQueryEndDate, lastPointAt)
    }
}
