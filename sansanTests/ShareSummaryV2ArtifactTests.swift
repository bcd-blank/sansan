//
//  ShareSummaryV2ArtifactTests.swift
//  sansanTests
//
//  Renders share-summary v2 + km-label cases into docs/share-summary-v2/impl/
//  when SANSAN_SHARE_SUMMARY_ARTIFACTS=1.
//

import CoreLocation
import XCTest
@testable import sansan

@MainActor
final class ShareSummaryV2ArtifactTests: XCTestCase {
    func testRenderShareSummaryV2Artifacts() async throws {
        // App Documents — host pulls via `simctl get_app_container` (clone sandboxes vanish).
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let outDir = docs.appendingPathComponent("share-summary-v2-impl", isDirectory: true)
        try? FileManager.default.removeItem(at: outDir)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let mapOptions = HikingShareMapExportOptions(
            showsDistanceMarkers: true,
            showsTimeMarkers: true,
            showsWeatherLabel: true,
            showsPhotoMarkers: false,
            showsPinnedThumbnails: false
        )

        // Weather slot counts
        for count in [1, 2, 3, 6, 8] {
            var record = makeRecord(weatherHours: count, memo: nil)
            record = SavedHikingSession(
                session: record.session,
                endedAt: record.endedAt,
                displayName: "[저장된 경로]",
                memo: nil,
                weather: record.weather
            )
            try await writeSummary(record: record, options: mapOptions, to: outDir, name: "weather-\(count).png")
        }

        // Memo variants
        try await writeSummary(
            record: makeRecord(weatherHours: 2, memo: nil),
            options: mapOptions,
            to: outDir,
            name: "memo-none.png"
        )
        try await writeSummary(
            record: makeRecord(
                weatherHours: 2,
                memo: "단풍이 절정이라 사진 찍느라 쉬엄쉬엄 걸었다."
            ),
            options: mapOptions,
            to: outDir,
            name: "memo-one-line.png"
        )
        try await writeSummary(
            record: makeRecord(
                weatherHours: 2,
                memo: "단풍이 절정이라 사진 찍느라 쉬엄쉬엄 걸었다. 계곡 바람이 시원했고 사람들 표정도 좋았다. 다음엔 조금 더 일찍 출발해서 정상에 오래 앉아 있고 싶다. 도시락도 챙기자."
            ),
            options: mapOptions,
            to: outDir,
            name: "memo-long.png"
        )
        try await writeSummary(
            record: makeRecord(
                weatherHours: 6,
                memo: "단풍이 절정이라 사진 찍느라 쉬엄쉬엄 걸었다. 계곡 바람이 시원했고 사람들 표정도 좋았다. 다음엔 조금 더 일찍 출발해서 정상에 오래 앉아 있고 싶다. 도시락도 챙기자."
            ),
            options: mapOptions,
            to: outDir,
            name: "weather-many-memo.png"
        )

        // Combined km-label cases (map snapshot with share-summary appearance)
        let canvas = CGSize(width: 430, height: 430 * 16 / 9)
        let record = makeRecord(weatherHours: 2, memo: nil)
        for (name, distance, time) in [
            ("km-label-both.png", true, true),
            ("km-label-km-only.png", true, false),
            ("km-label-time-only.png", false, true)
        ] as [(String, Bool, Bool)] {
            let options = HikingShareMapExportOptions(
                showsDistanceMarkers: distance,
                showsTimeMarkers: time,
                showsWeatherLabel: false,
                showsPhotoMarkers: false,
                showsPinnedThumbnails: false
            )
            let image = await HikingRouteSnapshotGenerator.fittedMapImage(
                record: record,
                canvasSize: canvas,
                pixelScale: 3,
                mapOptions: options,
                insetTop: 120,
                insetBottom: 352,
                insetLeft: 24,
                insetRight: 24,
                appearance: .shareSummary
            )
            XCTAssertNotNil(image, name)
            if let image, let data = image.pngData() {
                try data.write(to: outDir.appendingPathComponent(name), options: .atomic)
            }
        }

        let written = try FileManager.default.contentsOfDirectory(atPath: outDir.path)
        XCTAssertGreaterThanOrEqual(written.filter { $0.hasSuffix(".png") }.count, 10)
        print("ShareSummaryV2 artifacts → \(outDir.path): \(written.sorted())")
    }

    private func writeSummary(
        record: SavedHikingSession,
        options: HikingShareMapExportOptions,
        to dir: URL,
        name: String
    ) async throws {
        let image = await HikingRecordSummaryShareComposer.render(record: record, mapOptions: options)
        XCTAssertNotNil(image, name)
        guard let image, let data = image.pngData() else {
            XCTFail("missing png \(name)")
            return
        }
        try data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    private func makeRecord(weatherHours: Int, memo: String?) -> SavedHikingSession {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var points: [HikingPoint] = []
        let count = 120
        for i in 0..<count {
            let t = Double(i) / Double(count - 1)
            points.append(
                HikingPoint(
                    latitude: 37.6500 + t * 0.018,
                    longitude: 127.0100 + sin(t * .pi) * 0.008,
                    altitude: 80 + t * 200 + sin(t * 6) * 8,
                    timestamp: start.addingTimeInterval(t * 6420),
                    horizontalAccuracy: 5
                )
            )
        }
        let elevation = HikingSessionMetrics.elevationProfileSamples(from: points).map {
            HikingElevationChartSample(id: $0.id, distanceMeters: $0.distanceMeters, altitude: $0.altitude)
        }
        var heart: [HikingHeartRateChartSample] = []
        for (index, sample) in elevation.enumerated() {
            let bpm = 95 + sin(Double(index) / 8) * 30 + Double(index % 7)
            heart.append(
                HikingHeartRateChartSample(id: sample.id, distanceMeters: sample.distanceMeters, bpm: bpm)
            )
        }
        let distance = HikingSessionMetrics.horizontalDistance(from: points)
        let gain = HikingSessionMetrics.cumulativeElevationGain(from: points)
        let session = HikingSessionData(
            startedAt: start,
            totalDistance: distance,
            elapsedTime: 6420,
            currentAltitude: points.last?.altitude ?? 0,
            points: points,
            heartRateSamples: heart.enumerated().map { index, sample in
                HikingHeartRateSample(
                    id: sample.id,
                    bpm: sample.bpm,
                    timestamp: start.addingTimeInterval(Double(index) * 50)
                )
            },
            stepCount: 7535,
            activeEnergyKilocalories: 355,
            elevationGainMeters: gain,
            elevationProfile: elevation,
            heartRateProfile: heart,
            lastUpdated: start.addingTimeInterval(6420)
        )

        let codes = [0, 0, 2, 3, 61, 3, 0, 45]
        let temps = [12.0, 14.0, 14.0, 13.0, 11.0, 10.0, 9.0, 8.0]
        let hours: [HikingWeatherHourPoint] = (0..<weatherHours).map { index in
            HikingWeatherHourPoint(
                date: start.addingTimeInterval(Double(index) * 1800),
                wmoCode: codes[index % codes.count],
                temperatureCelsius: temps[index % temps.count]
            )
        }
        let weather = HikingRouteWeatherSnapshot(
            wmoCode: hours.first?.wmoCode ?? 0,
            temperatureCelsius: hours.first?.temperatureCelsius ?? 12,
            referenceDate: start,
            hours: hours,
            minimumTemperatureCelsius: temps.prefix(weatherHours).min(),
            maximumTemperatureCelsius: temps.prefix(weatherHours).max()
        )

        return SavedHikingSession(
            session: session,
            endedAt: start.addingTimeInterval(6420),
            displayName: "[저장된 경로]",
            memo: memo,
            weather: weather
        )
    }
}
