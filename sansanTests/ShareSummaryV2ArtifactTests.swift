//
//  ShareSummaryV2ArtifactTests.swift
//  sansanTests
//
//  Renders share-summary v2 review-fix captures into the app Documents
//  folder `share-summary-v2-impl4/` when SANSAN_SHARE_SUMMARY_ARTIFACTS=1.
//

import CoreLocation
import XCTest
@testable import sansan

@MainActor
final class ShareSummaryV2ArtifactTests: XCTestCase {
    /// Spec S11 — must overflow 3×350pt lines so tail '…' is visible.
    private let memoLongEllipsis =
        "아침 공기가 차서 마산역 앞에서 손난로를 켜고 출발했다. 산길은 아직 어두웠고 이슬이 신발 끝에 맺혔다. 정상에 도착하면 동쪽 능선 너머로 일출을 보고 싶다. 내려올 때는 단풍 터널에서 사진을 몇 장 더 남기자. 카페에서 따뜻한 차를 마시며 오늘 걸은 길을 천천히 되짚어 보기로 했다."

    private let memoOneLine = "단풍이 절정이라 사진 찍느라 쉬엄쉬엄 걸었다."

    func testRenderShareSummaryV2Artifacts() async throws {
        // Prefer host path. Shared app-group-style host folder (simulator can write under Documents/…);
        // also try TEST_RUNNER_ / env. Fallback: app Documents.
        let envOut = ProcessInfo.processInfo.environment["SANSAN_SHARE_SUMMARY_OUT"]
        let hostFallback = URL(fileURLWithPath: "/Users/jeongwook/Documents/sansan/build/share-summary-v2-impl4-artifacts", isDirectory: true)
        let outDir: URL
        if let envOut, !envOut.isEmpty {
            outDir = URL(fileURLWithPath: envOut, isDirectory: true)
        } else if FileManager.default.fileExists(atPath: hostFallback.deletingLastPathComponent().path) {
            outDir = hostFallback
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            outDir = docs.appendingPathComponent("share-summary-v2-impl4", isDirectory: true)
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
        weather-8 input hours (WMO@temp), first→last + even thin round(i·7/5) → indices [0,1,3,4,6,7]:
        \(weather8Inputs.joined(separator: ", "))
        """.write(to: outDir.appendingPathComponent("weather-8-inputs.txt"), atomically: true, encoding: .utf8)

        // Memo variants — S11 long fixture must need ≥3 lines for tail ellipsis.
        XCTAssertGreaterThanOrEqual(
            ShareSummaryTokens.memoLineCount(
                memoLongEllipsis,
                canvasWidth: HikingRecordShareDeviceMetrics.fullScreenBounds.width
            ),
            3,
            "S11 memo must need ≥3 lines"
        )
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

        // Long average-speed — must overflow 106pt at 28pt (e.g. 125'30"/km) and shrink alone (S1).
        try await writeSummary(
            record: makeRecord(weatherHours: 2, memo: nil, paceOverride: 125.5),
            options: mapOptions,
            to: outDir,
            name: "avg-speed-long.png"
        )

        // impl4 extras: roads under attribution (halo check) + km near right edge.
        try await writeSummary(
            record: makeRecord(weatherHours: 2, memo: nil, routeStyle: .urbanAttribution),
            options: mapOptions,
            to: outDir,
            name: "attribution-path.png"
        )
        try await writeSummary(
            record: makeRecord(weatherHours: 0, memo: nil, routeStyle: .eastWestLong),
            options: HikingShareMapExportOptions(
                showsDistanceMarkers: true,
                showsTimeMarkers: true,
                showsWeatherLabel: false,
                showsPhotoMarkers: false,
                showsPinnedThumbnails: false
            ),
            to: outDir,
            name: "km-label-right-edge.png"
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
        XCTAssertGreaterThanOrEqual(written.filter { $0.hasSuffix(".png") }.count, 14)
        print("ShareSummaryV2 impl4 artifacts → \(outDir.path): \(written.sorted())")
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

    private enum RouteStyle {
        /// Default N–S bulge used by impl3 captures.
        case standard
        /// Dense Seoul block so basemap roads cross attribution (impl4 #15).
        case urbanAttribution
        /// ~3.5 km east–west so a late km capsule sits near the right inset.
        case eastWestLong
    }

    /// - Parameter paceOverride: minutes/km used to force elapsed time for a long pace string.
    private func makeRecord(
        weatherHours: Int,
        memo: String?,
        paceOverride: Double? = nil,
        routeStyle: RouteStyle = .standard
    ) -> SavedHikingSession {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let count = 120
        let targetDistanceMeters: Double = {
            switch routeStyle {
            case .eastWestLong: return 3_500
            case .urbanAttribution: return 2_200
            case .standard: return paceOverride != nil ? 2_500 : 0
            }
        }()
        let latSpan = targetDistanceMeters > 0 ? (targetDistanceMeters / 111_000.0) : 0.018
        var coords: [(lat: Double, lon: Double, alt: Double)] = []
        for i in 0..<count {
            let t = Double(i) / Double(count - 1)
            switch routeStyle {
            case .eastWestLong:
                let lonSpan = 3.5 / (111.0 * cos(37.5665 * .pi / 180.0))
                coords.append(
                    (
                        37.5665 + sin(t * .pi) * 0.0015,
                        126.9780 + t * lonSpan,
                        40 + t * 30 + sin(t * 4) * 4
                    )
                )
            case .urbanAttribution:
                coords.append(
                    (
                        37.5665 + t * 0.012,
                        126.9780 + sin(t * .pi * 2) * 0.006,
                        30 + t * 40 + sin(t * 5) * 3
                    )
                )
            case .standard:
                coords.append(
                    (
                        37.6500 + t * latSpan,
                        127.0100 + sin(t * .pi) * 0.008,
                        80 + t * 200 + sin(t * 6) * 8
                    )
                )
            }
        }
        // Provisional points for distance; timestamps filled after pace retarget.
        var points: [HikingPoint] = coords.enumerated().map { index, c in
            HikingPoint(
                latitude: c.lat,
                longitude: c.lon,
                altitude: c.alt,
                timestamp: start.addingTimeInterval(Double(index)),
                horizontalAccuracy: 5
            )
        }
        let distance = HikingSessionMetrics.horizontalDistance(from: points)
        let gain = HikingSessionMetrics.cumulativeElevationGain(from: points)
        let elapsedFinal: TimeInterval
        if let paceOverride, distance >= 10 {
            elapsedFinal = paceOverride * 60.0 * (distance / 1_000.0)
        } else {
            elapsedFinal = 6420
        }
        points = coords.enumerated().map { index, c in
            let t = Double(index) / Double(count - 1)
            return HikingPoint(
                latitude: c.lat,
                longitude: c.lon,
                altitude: c.alt,
                timestamp: start.addingTimeInterval(t * elapsedFinal),
                horizontalAccuracy: 5
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
        let session = HikingSessionData(
            startedAt: start,
            totalDistance: distance,
            elapsedTime: elapsedFinal,
            currentAltitude: points.last?.altitude ?? 0,
            points: points,
            heartRateSamples: heart.enumerated().map { index, sample in
                HikingHeartRateSample(
                    id: sample.id,
                    bpm: sample.bpm,
                    timestamp: start.addingTimeInterval(Double(index) * max(elapsedFinal / Double(count), 1))
                )
            },
            stepCount: 7535,
            activeEnergyKilocalories: 355,
            elevationGainMeters: gain,
            elevationProfile: elevation,
            heartRateProfile: heart,
            lastUpdated: start.addingTimeInterval(elapsedFinal)
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
            endedAt: start.addingTimeInterval(elapsedFinal),
            displayName: "[저장된 경로]",
            memo: memo,
            weather: weather
        )
    }
}
