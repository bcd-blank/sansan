//
//  HikingRouteWeatherServiceTests.swift
//  sansanTests
//

import XCTest
@testable import sansan

final class HikingRouteWeatherServiceTests: XCTestCase {
    private let hour: TimeInterval = 3600

    func testSnapshotPrefersShowerDuringHikeOverClearStart() {
        let start = Date(timeIntervalSince1970: 1_776_240_000) // 2026-04-13 09:00 KST 근처
        let samples = [
            HourlyWeatherSample(date: start, temperatureCelsius: 22, weatherCode: 0, precipitationMillimeters: 0, showersMillimeters: 0),
            HourlyWeatherSample(date: start.addingTimeInterval(hour), temperatureCelsius: 21, weatherCode: 80, precipitationMillimeters: 1.2, showersMillimeters: 1.2),
            HourlyWeatherSample(date: start.addingTimeInterval(hour * 2), temperatureCelsius: 20, weatherCode: 2, precipitationMillimeters: 0, showersMillimeters: 0),
        ]

        let snapshot = HikingRouteWeatherService.snapshot(
            from: samples,
            start: start,
            end: start.addingTimeInterval(hour * 2.5)
        )

        XCTAssertEqual(snapshot?.wmoCode, 80)
        XCTAssertEqual(snapshot?.conditionLabel, "소나기")
        XCTAssertEqual(snapshot?.changeSummary, "맑음 → 소나기 → 구름 조금")
        XCTAssertTrue(snapshot?.hasConditionChanges == true)
        XCTAssertEqual(snapshot?.segments.count, 3)
        XCTAssertEqual(snapshot?.hours.count, 3)
        XCTAssertEqual(snapshot?.hours.map(\.temperatureCelsius), [22, 21, 20])
        XCTAssertEqual(snapshot?.temperatureCelsius ?? 0, 21, accuracy: 0.01)
        XCTAssertEqual(snapshot?.minimumTemperatureCelsius, 20)
        XCTAssertEqual(snapshot?.maximumTemperatureCelsius, 22)
        XCTAssertTrue(snapshot?.hasTemperatureExtremes == true)
        XCTAssertTrue(snapshot?.showsTemperatureRange == true)
    }

    func testSnapshotOverridesClearCodeWhenPrecipitationIsPresent() {
        let start = Date(timeIntervalSince1970: 1_776_240_000)
        let samples = [
            HourlyWeatherSample(date: start, temperatureCelsius: 19, weatherCode: 1, precipitationMillimeters: 0.8, showersMillimeters: 0.6),
        ]

        let snapshot = HikingRouteWeatherService.snapshot(
            from: samples,
            start: start,
            end: start.addingTimeInterval(hour)
        )

        XCTAssertEqual(snapshot?.wmoCode, 80)
    }

    func testSnapshotIgnoresWeatherOutsideHikeWindow() {
        let start = Date(timeIntervalSince1970: 1_776_240_000)
        let samples = [
            HourlyWeatherSample(date: start.addingTimeInterval(-hour * 3), temperatureCelsius: 18, weatherCode: 95, precipitationMillimeters: 5, showersMillimeters: 0),
            HourlyWeatherSample(date: start, temperatureCelsius: 22, weatherCode: 0, precipitationMillimeters: 0, showersMillimeters: 0),
        ]

        let snapshot = HikingRouteWeatherService.snapshot(
            from: samples,
            start: start,
            end: start.addingTimeInterval(hour)
        )

        XCTAssertEqual(snapshot?.wmoCode, 0)
        XCTAssertEqual(snapshot?.conditionLabel, "맑음")
        XCTAssertEqual(snapshot?.changeSummary, "맑음")
        XCTAssertFalse(snapshot?.hasConditionChanges == true)
    }

    func testSnapshotMergesConsecutiveHoursWithSameLabel() {
        let start = Date(timeIntervalSince1970: 1_776_240_000)
        let samples = [
            HourlyWeatherSample(date: start, temperatureCelsius: 22, weatherCode: 1, precipitationMillimeters: 0, showersMillimeters: 0),
            HourlyWeatherSample(date: start.addingTimeInterval(hour), temperatureCelsius: 21, weatherCode: 3, precipitationMillimeters: 0, showersMillimeters: 0),
            HourlyWeatherSample(date: start.addingTimeInterval(hour * 2), temperatureCelsius: 20, weatherCode: 2, precipitationMillimeters: 0, showersMillimeters: 0),
        ]

        let snapshot = HikingRouteWeatherService.snapshot(
            from: samples,
            start: start,
            end: start.addingTimeInterval(hour * 2.5)
        )

        XCTAssertEqual(snapshot?.segments.count, 1)
        XCTAssertEqual(snapshot?.changeSummary, "구름 조금")
        XCTAssertEqual(snapshot?.hours.map(\.temperatureCelsius), [22, 21, 20])
    }

    func testChangeSummaryDedupesOscillatingConditions() {
        let start = Date(timeIntervalSince1970: 1_776_240_000)
        let samples = [
            HourlyWeatherSample(date: start, temperatureCelsius: 18, weatherCode: 0, precipitationMillimeters: 0, showersMillimeters: 0),
            HourlyWeatherSample(date: start.addingTimeInterval(hour), temperatureCelsius: 19, weatherCode: 2, precipitationMillimeters: 0, showersMillimeters: 0),
            HourlyWeatherSample(date: start.addingTimeInterval(hour * 2), temperatureCelsius: 20, weatherCode: 0, precipitationMillimeters: 0, showersMillimeters: 0),
            HourlyWeatherSample(date: start.addingTimeInterval(hour * 3), temperatureCelsius: 17, weatherCode: 3, precipitationMillimeters: 0, showersMillimeters: 0),
        ]

        let snapshot = HikingRouteWeatherService.snapshot(
            from: samples,
            start: start,
            end: start.addingTimeInterval(hour * 3.5)
        )

        XCTAssertEqual(snapshot?.changeSummary, "맑음 → 구름 조금")
        XCTAssertEqual(snapshot?.formattedAverageTemperature, "평균 19°")
        XCTAssertEqual(snapshot?.formattedTemperatureRange, "최저 17°  최고 20°")
    }

    func testLegacySnapshotDecodesWithoutTemperatureExtremes() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let original = HikingRouteWeatherSnapshot(
            wmoCode: 0,
            temperatureCelsius: 16.4,
            referenceDate: Date(timeIntervalSince1970: 1_776_240_000)
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(original)) as? [String: Any]
        )
        object.removeValue(forKey: "minimumTemperatureCelsius")
        object.removeValue(forKey: "maximumTemperatureCelsius")
        let snapshot = try decoder.decode(
            HikingRouteWeatherSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertFalse(snapshot.hasTemperatureExtremes)
        XCTAssertEqual(snapshot.minimumTemperatureCelsius, 16.4, accuracy: 0.01)
        XCTAssertEqual(snapshot.maximumTemperatureCelsius, 16.4, accuracy: 0.01)
        XCTAssertEqual(snapshot.formattedAverageTemperature, "평균 16°")
        XCTAssertFalse(snapshot.showsTemperatureRange)
        XCTAssertTrue(snapshot.hours.isEmpty)
        XCTAssertTrue(snapshot.needsWeatherRefresh)
    }

    func testSnapshotKeepsOnlyTemperatureAndConditionChanges() {
        let start = Date(timeIntervalSince1970: 1_776_240_000)
        let samples = [
            HourlyWeatherSample(date: start, temperatureCelsius: 22.1, weatherCode: 1, precipitationMillimeters: 0, showersMillimeters: 0),
            HourlyWeatherSample(date: start.addingTimeInterval(hour), temperatureCelsius: 22.4, weatherCode: 3, precipitationMillimeters: 0, showersMillimeters: 0),
            HourlyWeatherSample(date: start.addingTimeInterval(hour * 2), temperatureCelsius: 21.0, weatherCode: 2, precipitationMillimeters: 0, showersMillimeters: 0),
            HourlyWeatherSample(date: start.addingTimeInterval(hour * 3), temperatureCelsius: 21.2, weatherCode: 80, precipitationMillimeters: 1.0, showersMillimeters: 1.0),
            HourlyWeatherSample(date: start.addingTimeInterval(hour * 4), temperatureCelsius: 20.8, weatherCode: 80, precipitationMillimeters: 0.4, showersMillimeters: 0.4),
        ]

        let snapshot = HikingRouteWeatherService.snapshot(
            from: samples,
            start: start,
            end: start.addingTimeInterval(hour * 4.5)
        )

        XCTAssertEqual(snapshot?.hours.count, 3)
        XCTAssertEqual(snapshot?.hours.map { Int($0.temperatureCelsius.rounded()) }, [22, 21, 21])
        XCTAssertEqual(
            snapshot?.hours.map { HikingRouteWeatherSnapshot.conditionLabel(for: $0.wmoCode) },
            ["구름 조금", "구름 조금", "소나기"]
        )
    }
}
