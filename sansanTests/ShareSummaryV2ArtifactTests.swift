//
//  ShareSummaryV2ArtifactTests.swift
//  sansanTests
//
//  Renders share-summary v2 review-fix captures into the app Documents
//  folder `share-summary-v2-impl2/` when SANSAN_SHARE_SUMMARY_ARTIFACTS=1.
//

import CoreLocation
import XCTest
@testable import sansan

@MainActor
final class ShareSummaryV2ArtifactTests: XCTestCase {
    /// Spec S11 review fixture — long enough to ellipsize at 3 lines.
    private let memoLongEllipsis =
        "아침 공기가 차서 마산역 앞에서 손난로를 켜고 출발했다. 산길은 아직 어두웠고 이슬이 신발 끝에 맺혔다. 정상에 도착하면 동쪽 능선 너머로 일출을 보고 싶다. 내려올 때는 단풍 터널에서 사진을 몇 장 더 남기자."

    private let memoOneLine = "단풍이 절정이라 사진 찍느라 쉬엄쉬엄 걸었다."

    func testRenderShareSummaryV2Artifacts() async throws {
        // Prefer host path (clone Documents vanish). Fallback: app Documents for manual pull.
        let envOut = ProcessInfo.processInfo.environment["SANSAN_SHARE_SUMMARY_OUT"]
        let outDir: URL
        if let envOut, !envOut.isEmpty {
            outDir = URL(fileURLWithPath: envOut, isDirectory: true)
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            outDir = docs.appendingPathComponent("share-summary-v2-impl2", isDirectory: true)
        }
        try? FileManager.default.removeItem(at: outDir)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let mapOptions = HikingShareMapExportOptions(
            showsDistanceMarkers: true,
            showsTimeMarkers: true,
            showsWeatherLabel: true,
            showsPhotoMarkers: false,
            showsPinnedThumbnails: false
        )

        // Weather slot counts (8 → thinned to 6; inputs documented in weather-8-inputs.txt)
        var weather8Inputs: [String] = []
        for count in [1, 2, 3, 6, 8] {
            let record = makeRecord(weatherHours: count, memo: nil, paceOverride: nil)
            if count == 8, let hours = record.weather?.timelineHours {
                weather8Inputs = hours.map { hour in
                    "\(hour.wmoCode)@\(Int(hour.temperatureCelsius.rounded()))°"
                }
            }
            try await writeSummary(record: record, options: mapOptions, to: outDir, name: "weather-\(count).png")
        }
        try """
        weather-8 input hours (WMO@temp), first→last kept + even thin → 6:
        \(weather8Inputs.joined(separator: ", "))
        """.write(to: outDir.appendingPathComponent("weather-8-inputs.txt"), atomically: true, encoding: .utf8)

        // Memo variants
        try await writeSummary(
            record: makeRecord(weatherHours: 2, memo: nil),
            options: mapOptions,
            to: outDir,
            name: "memo-none.png"
        )
        try await writeSummary(
            record: makeRecord(weatherHours: 2, memo: memoOneLine),
            options: mapOptions,
            to: outDir,
            name: "memo-one-line.png"
        )
        try await writeSummary(
            record: makeRecord(weatherHours: 2, memo: memoLongEllipsis),
            options: mapOptions,
            to: outDir,
            name: "memo-long.png"
        )
        try await writeSummary(
            record: makeRecord(weatherHours: 6, memo: memoLongEllipsis),
            options: mapOptions,
            to: outDir,
            name: "weather-many-memo.png"
        )

        // Long average-speed / pace (S1 worst-case style string via slow pace)
        try await writeSummary(
            record: makeRecord(weatherHours: 2, memo: nil, paceOverride: 42.55),
            options: mapOptions,
            to: outDir,
            name: "avg-speed-long.png"
        )

        // Combined km-label cases (map snapshot with share-summary appearance)
        let canvas = ShareSummaryTokens.canvasSize(widthPoints: 430, pixelScale: 3)
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
                insetTop: ShareSummaryTokens.mapTopInset(memoLineCount: 0),
                insetBottom: ShareSummaryTokens.mapBottomInset,
                insetLeft: 24,
                insetRight: 24,
                appearance: .shareSummary,
                fadeSolidEndY: ShareSummaryTokens.fadeSolidEnd(memoLineCount: 0)
            )
            XCTAssertNotNil(image, name)
            if let image, let data = image.pngData() {
                try data.write(to: outDir.appendingPathComponent(name), options: .atomic)
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }

        let written = try FileManager.default.contentsOfDirectory(atPath: outDir.path)
        XCTAssertGreaterThanOrEqual(written.filter { $0.hasSuffix(".png") }.count, 12)
        print("ShareSummaryV2 impl2 artifacts → \(outDir.path): \(written.sorted())")
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
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// - Parameter paceOverride: minutes/km used to force elapsed time for a long pace string.
    private func makeRecord(
        weatherHours: Int,
        memo: String?,
        paceOverride: Double? = nil
    ) -> SavedHikingSession {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var points: [HikingPoint] = []
        let count = 120
        let targetDistanceMeters: Double
        let elapsed: TimeInterval
        if let paceOverride {
            // ~2.5km at the requested pace → averageSpeedValueText uses that pace.
            targetDistanceMeters = 2_500
            elapsed = paceOverride * 60.0 * (targetDistanceMeters / 1_000.0)
        } else {
            targetDistanceMeters = 0
            elapsed = 6420
        }
        for i in 0..<count {
            let t = Double(i) / Double(count - 1)
            let latSpan = targetDistanceMeters > 0 ? (targetDistanceMeters / 111_000.0) : 0.018
            points.append(
                HikingPoint(
                    latitude: 37.6500 + t * latSpan,
                    longitude: 127.0100 + sin(t * .pi) * 0.008,
                    altitude: 80 + t * 200 + sin(t * 6) * 8,
                    timestamp: start.addingTimeInterval(t * elapsed),
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
            elapsedTime: elapsed,
            currentAltitude: points.last?.altitude ?? 0,
            points: points,
            heartRateSamples: heart.enumerated().map { index, sample in
                HikingHeartRateSample(
                    id: sample.id,
                    bpm: sample.bpm,
                    timestamp: start.addingTimeInterval(Double(index) * max(elapsed / Double(count), 1))
                )
            },
            stepCount: 7535,
            activeEnergyKilocalories: 355,
            elevationGainMeters: gain,
            elevationProfile: elevation,
            heartRateProfile: heart,
            lastUpdated: start.addingTimeInterval(elapsed)
        )

        // Documented weather-8 palette (finding 18): sun/sun/cloud-sun/cloud/rain/cloud/sun/fog
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
            endedAt: start.addingTimeInterval(elapsed),
            displayName: "[저장된 경로]",
            memo: memo,
            weather: weather
        )
    }
}
