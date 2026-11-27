#if os(iOS)
import Foundation
import UIKit
import CoreLocation
import SwiftUI

#if DEBUG
/// #73 DEBUG 전용. release 빌드에서는 `#else` no-op만 남습니다.
/// 실행 인자: `-UITestSkipHealthAuth` / `-UITestSeedRecords`
enum UITestSupport {
    static let skipHealthAuth = CommandLine.arguments.contains("-UITestSkipHealthAuth")
    static let seedRecords = CommandLine.arguments.contains("-UITestSeedRecords")

    /// 고정 UUID — 재실행 시 동일 시드, 실기록 wipe 금지.
    private static let seedSessionID = UUID(uuidString: "00000000-0000-4000-8000-00000000a001")!
    private static let seedPhotoID = UUID(uuidString: "00000000-0000-4000-8000-00000000b001")!

    static var gahyeonsanSeedID: UUID { UITestMountainPathFixtures.gahyeonsan.id }
    static var saryangdoSeedID: UUID { UITestMountainPathFixtures.saryangdo.id }
    static var samaksanSeedID: UUID { UITestMountainPathFixtures.samaksan.id }
    static var gamajicheonSeedID: UUID { UITestMountainPathFixtures.gamajicheon.id }
    /// Samsung backup SoT for pager previews (read-only device id).
    static var hangjunaruSeedID: UUID {
        UUID(uuidString: "26EDF0AC-CD95-44E6-9E32-18930E5A4DB7")!
    }

    private static var didSeedPlacementRecords = false

    static func applyIfNeeded() {
        UITestMapCaptureHooks.installIfNeeded()
        // Seed is optional; exports still run when their flags are set (e.g. hangjunaru inject).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard UserDataPaths.isUserSelected else { return }
            if seedRecords, !didSeedPlacementRecords {
                didSeedPlacementRecords = true
                reseedsPlacementRecords()
            }
            // Hangjunaru JSON fixture is always available for pager export (no device needed).
            seedHangjunaruFixtureIfNeeded()
            exportSummariesIfNeeded()
            exportSaveStylesIfNeeded()
            exportPhotoOffEvidenceIfNeeded()
            anrSelfcrossGateIfNeeded()
        }
    }

    /// `-SANSAN_ANR_SELFCROSS_GATE` — real-store only (no seed). Benches self-cross,
    /// probes MainActor hangs ≥250ms during stretch rebuild, exports 3 image-save
    /// styles × longest + one other record.
    private static func anrSelfcrossGateIfNeeded() {
        let env = ProcessInfo.processInfo.environment["SANSAN_ANR_SELFCROSS_GATE"]
        let arg = ProcessInfo.processInfo.arguments.contains("-SANSAN_ANR_SELFCROSS_GATE")
        guard env == "1" || arg else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            let store = HikingRecordStore.shared
            store.reloadForCurrentUser()
            let records = store.records.sorted { $0.session.points.count > $1.session.points.count }
            let dir = UserDataPaths.documentsDirectory
                .appendingPathComponent("anr-selfcross-gate", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            guard !records.isEmpty else {
                try? "FAIL empty store (need real backup, no seed)\n"
                    .write(to: dir.appendingPathComponent("GATE_DONE.txt"), atomically: true, encoding: .utf8)
                return
            }

            var lines: [String] = ["# anr-selfcross-gate"]
            var hangOver250 = 0
            var maxFirstMs = 0.0
            var allUnder1s = true
            for record in records {
                let coords = record.session.points.map(\.coordinate)
                guard coords.count >= 2 else { continue }
                let name = record.displayName ?? record.id.uuidString
                // First path display = map-first continuous dual-rail on MainActor
                // (prepareRouteDisplayData → rebuildRouteRailLayers sync path).
                let tPaint = CFAbsoluteTimeGetCurrent()
                let quickCoords = record.session.points.map(\.coordinate)
                let continuousRails = (casing: quickCoords, fill: quickCoords)
                let firstPaintMs = (CFAbsoluteTimeGetCurrent() - tPaint) * 1000
                _ = continuousRails.casing.count

                // Start detached stretch compute, probe MainActor responsiveness during it.
                let computeTask = Task.detached(priority: .userInitiated) {
                    RouteSelfCrossing.chronologicalCoordinateStretches(in: coords)
                }
                let pingStart = CFAbsoluteTimeGetCurrent()
                let hangMs: Double = await withCheckedContinuation { cont in
                    DispatchQueue.global(qos: .userInitiated).async {
                        // Yield so detached work is scheduled, then ping main.
                        usleep(5_000)
                        DispatchQueue.main.async {
                            let late = (CFAbsoluteTimeGetCurrent() - pingStart) * 1000
                            cont.resume(returning: late)
                        }
                    }
                }
                let t0 = CFAbsoluteTimeGetCurrent()
                let stretches = await computeTask.value
                let computeMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000 + 5 // include usleep slack wall
                if hangMs >= 250 { hangOver250 += 1 }
                if firstPaintMs >= 1000 { allUnder1s = false }
                maxFirstMs = max(maxFirstMs, firstPaintMs)
                lines.append(
                    String(
                        format: "record=%@ pts=%d stretches=%d firstPaintMs=%.1f computeMs=%.1f hangProbeMs=%.1f",
                        name, coords.count, stretches.count, firstPaintMs, computeMs, hangMs
                    )
                )
            }
            lines.append(
                String(
                    format: "summary records=%d maxFirstPaintMs=%.1f hang≥250=%d allFirstPaint<1s=%@",
                    records.count, maxFirstMs, hangOver250, allUnder1s ? "yes" : "no"
                )
            )

            let exportMapOptions = HikingShareMapExportOptions(
                showsDistanceMarkers: true,
                showsTimeMarkers: true,
                showsWeatherLabel: false,
                showsPhotoMarkers: false,
                showsPinnedThumbnails: false
            )
            let styles: [(HikingRecordImageSaveStyle, String)] = [
                (.card, "data-card"),
                (.summary, "simple-grey"),
                (.simpleColor, "simple-color"),
            ]
            let previous = HikingRecordImageSavePreferences.style
            defer { HikingRecordImageSavePreferences.style = previous }
            var targets: [(SavedHikingSession, String)] = []
            if let longest = records.first {
                let slug = (longest.displayName ?? "longest")
                    .replacingOccurrences(of: " ", with: "-")
                targets.append((longest, slug))
            }
            if let other = records.dropFirst().first(where: { $0.session.points.count >= 200 })
                ?? records.dropFirst().first {
                let slug = (other.displayName ?? "other")
                    .replacingOccurrences(of: " ", with: "-")
                targets.append((other, slug))
            }
            for (record, slug) in targets {
                for (style, styleSlug) in styles {
                    HikingRecordImageSavePreferences.style = style
                    let tSave = CFAbsoluteTimeGetCurrent()
                    let image = await store.shareImage(
                        for: record.id,
                        mapOptions: exportMapOptions,
                        fullScreen: true
                    )
                    let saveMs = (CFAbsoluteTimeGetCurrent() - tSave) * 1000
                    if let image, let data = image.pngData() {
                        let file = "ios-\(slug)-\(styleSlug).png"
                        try? data.write(to: dir.appendingPathComponent(file), options: .atomic)
                        lines.append(
                            String(format: "save OK %@ %.1fms %dx%d", file, saveMs, Int(image.size.width), Int(image.size.height))
                        )
                    } else {
                        lines.append(String(format: "save FAIL %@ %.1fms", "\(slug)-\(styleSlug)", saveMs))
                    }
                }
            }

            let body = lines.joined(separator: "\n") + "\n"
            try? body.write(to: dir.appendingPathComponent("gate-log.txt"), atomically: true, encoding: .utf8)
            try? body.write(to: dir.appendingPathComponent("GATE_DONE.txt"), atomically: true, encoding: .utf8)
            print("[anr-selfcross-gate]\n\(body)")
        }
    }

    private static func reseedsPlacementRecords() {
        let store = HikingRecordStore.shared
        // Warm relaunch: keep existing cached fixtures — wiping forced no-cache opens
        // and 3–9s prepare while other seeds blocked the main actor.
        let fixturesReady = UITestMountainPathFixtures.all.allSatisfy { fixture in
            store.records.contains {
                $0.id == fixture.id && $0.session.hasPersistedDisplayCache
            }
        }
        if fixturesReady {
            seedHangjunaruFixtureIfNeeded()
            return
        }
        let ids = UITestMountainPathFixtures.all.map(\.id) + [seedSessionID, hangjunaruSeedID]
        for id in ids {
            if store.records.contains(where: { $0.id == id }) {
                store.delete(id: id)
            }
        }
        seedDummyRecordIfNeeded()
        // Seed the screenshot-target fixture first so detail open hits display cache
        // before other mountains' finalizeForPersistence blocks the main actor.
        let priorityID = AppStoreScreenshotMode.current?.opensSeededDetailRecordID
        let ordered = UITestMountainPathFixtures.all.sorted { a, b in
            (a.id == priorityID ? 0 : 1) < (b.id == priorityID ? 0 : 1)
        }
        for fixture in ordered {
            seedFixture(fixture)
        }
        seedHangjunaruFixtureIfNeeded()
    }

    /// Bundled `Resources/uitest-fixtures/hangjunaru.json` (Samsung backup id 26edf0ac…).
    private static func seedHangjunaruFixtureIfNeeded() {
        let store = HikingRecordStore.shared
        if store.records.contains(where: { $0.id == hangjunaruSeedID }) { return }
        guard UserDataPaths.isUserSelected else { return }
        guard let url = Bundle.main.url(
            forResource: "hangjunaru",
            withExtension: "json",
            subdirectory: "uitest-fixtures"
        ) ?? Bundle.main.url(forResource: "hangjunaru", withExtension: "json") else {
            print("[uitest] hangjunaru.json fixture missing from bundle")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let record = try decoder.decode(SavedHikingSession.self, from: data)
            store.importSeededRecord(record)
            print("[uitest] seeded hangjunaru \(record.displayName ?? "?") pts=\(record.session.points.count)")
        } catch {
            print("[uitest] hangjunaru seed failed: \(error)")
        }
    }

    static var shouldSkipHealthAuthorization: Bool { skipHealthAuth }

    private static func seedDummyRecordIfNeeded() {
        let store = HikingRecordStore.shared
        if store.records.contains(where: { $0.id == seedSessionID }) { return }
        guard UserDataPaths.isUserSelected else { return }

        // Fixed Asia/Seoul wall clock — size-parity A001 SoT is 09:33–10:23 (50m), never Date()-relative.
        let started = fixedA001StartedAt()
        let coords: [(Double, Double, Double)] = [
            (37.5665, 126.9780, 40),
            (37.5670, 126.9790, 55),
            (37.5680, 126.9805, 80),
            (37.5690, 126.9820, 95),
            (37.5700, 126.9835, 110),
            (37.5710, 126.9850, 120),
        ]
        let points: [HikingPoint] = coords.enumerated().map { i, c in
            HikingPoint(
                latitude: c.0,
                longitude: c.1,
                altitude: c.2,
                timestamp: started.addingTimeInterval(Double(i) * 600)
            )
        }
        let image = syntheticTrailImage()
        let filename = "\(seedPhotoID.uuidString).jpg"
        do {
            try HikingTrailPhotoStore.saveJPEG(image, sessionID: seedSessionID, filename: filename)
        } catch {
            return
        }
        let mid = points[2]
        let photo = HikingTrailPhoto(
            id: seedPhotoID,
            latitude: mid.latitude,
            longitude: mid.longitude,
            timestamp: mid.timestamp,
            filename: filename
        )
        let session = HikingSessionData(
            sessionID: seedSessionID,
            state: .idle,
            startedAt: started,
            totalDistance: 1_250,
            elapsedTime: 3_000,
            currentAltitude: 120,
            points: points,
            photos: [photo],
            stepCount: 1_800,
            activeEnergyKilocalories: 160,
            elevationGainMeters: 80
        )
        store.save(session)
    }

    /// JW 실경로(jw-feedback 장면과 동일 기록) — 파일명=산 이름, 오표기 금지.
    private static func seedFixture(_ fixture: UITestMountainPathFixtures.Fixture) {
        let store = HikingRecordStore.shared
        if store.records.contains(where: { $0.id == fixture.id }) { return }
        guard UserDataPaths.isUserSelected else { return }

        // Fixed Asia/Seoul wall clock (match Android label-placement/*.json) so share
        // timeline stays 「오후 9:02/9:54」 across reinstall — never Date()-relative.
        let started = fixedSeedStartedAt(for: fixture)
        let points: [HikingPoint] = fixture.points.map { p in
            HikingPoint(
                latitude: p.lat,
                longitude: p.lon,
                altitude: p.alt,
                timestamp: started.addingTimeInterval(p.offset)
            )
        }
        var measured: Double = 0
        for i in 1..<points.count {
            let a = CLLocation(latitude: points[i - 1].latitude, longitude: points[i - 1].longitude)
            let b = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            measured += b.distance(from: a)
        }
        var seededPoints = points
        var totalDistance = max(measured, fixture.totalDistance * 0.98)
        var elapsedTime = fixture.elapsedTime
        // v3 sample lock (match Android ImageSaveStyleCapture): 4.20 km · 4km 48:26.
        if fixture.id == UITestMountainPathFixtures.gamajicheon.id {
            totalDistance = 4_200
            // splitElapsedLabel truncates — aim slightly above 2906 so label reads 48:26.
            seededPoints = scalePointsForKm4Arrival(
                points: points,
                startedAt: started,
                targetElapsedSec: 48 * 60 + 26 + 0.75
            )
            if let last = seededPoints.last {
                elapsedTime = last.timestamp.timeIntervalSince(started)
            }
        }
        var session = HikingSessionData(
            sessionID: fixture.id,
            state: .idle,
            startedAt: started,
            totalDistance: totalDistance,
            elapsedTime: elapsedTime,
            currentAltitude: seededPoints.last?.altitude ?? 0,
            points: seededPoints,
            photos: [],
            stepCount: fixture.stepCount > 0 ? fixture.stepCount : Int(measured / 0.7),
            activeEnergyKilocalories: fixture.activeEnergyKilocalories,
            elevationGainMeters: fixture.elevationGainMeters
        )
        // Lightweight display cache (coords + km) so detail open is a ≤1s cache hit
        // without main-actor elevation smoothing during multi-fixture seed.
        let routeCoords = HikingSessionMetrics.routeCoordinates(from: seededPoints)
        let maxCoords = HikingSessionDisplayCacheBuilder.maxDisplayRouteCoordinates
        let stride = max(1, routeCoords.count / maxCoords)
        let displayCoords = routeCoords.enumerated().compactMap { idx, c -> HikingDisplayCoordinate? in
            guard idx % stride == 0 || idx == routeCoords.count - 1 else { return nil }
            return HikingDisplayCoordinate(latitude: c.latitude, longitude: c.longitude)
        }
        let kmMarkers = HikingSessionMetrics.kilometerMarkerPlacements(from: seededPoints)
        session.applyDisplayCache(
            HikingSessionDisplayCacheBuilder.Built(
                elevationGainMeters: fixture.elevationGainMeters,
                elevationProfile: nil,
                heartRateProfile: nil,
                displayRouteCoordinates: displayCoords,
                kilometerMarkers: kmMarkers,
                nearbySummits: []
            )
        )
        store.save(session)
        store.renameRecord(id: fixture.id, title: fixture.title)
    }

    /// Uniformly scale point timestamps from session origin so the 4 km crossing
    /// lands at `targetElapsedSec` (pause-aware via `HikingSessionMetrics.elapsedSeconds`).
    private static func scalePointsForKm4Arrival(
        points: [HikingPoint],
        startedAt: Date,
        targetElapsedSec: TimeInterval
    ) -> [HikingPoint] {
        guard points.count >= 2, targetElapsedSec > 0 else { return points }
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        var distances: [Double] = [0]
        for i in 1..<sorted.count {
            let a = CLLocation(latitude: sorted[i - 1].latitude, longitude: sorted[i - 1].longitude)
            let b = CLLocation(latitude: sorted[i].latitude, longitude: sorted[i].longitude)
            distances.append(distances[i - 1] + b.distance(from: a))
        }
        var arrival: Date?
        for index in 1..<sorted.count {
            let segmentStart = distances[index - 1]
            let segmentEnd = distances[index]
            let segment = segmentEnd - segmentStart
            guard segment > 0 else { continue }
            if segmentStart < 4_000, segmentEnd >= 4_000 {
                let ratio = (4_000 - segmentStart) / segment
                let start = sorted[index - 1].timestamp
                let end = sorted[index].timestamp
                arrival = start.addingTimeInterval(end.timeIntervalSince(start) * ratio)
                break
            }
        }
        guard let arrival else { return points }
        let currentElapsed = HikingSessionMetrics.elapsedSeconds(
            at: arrival,
            startedAt: startedAt,
            segmentBreaks: nil
        )
        guard currentElapsed > 0.5 else { return points }
        let scale = targetElapsedSec / currentElapsed
        return points.map { point in
            let delta = point.timestamp.timeIntervalSince(startedAt)
            return HikingPoint(
                id: point.id,
                latitude: point.latitude,
                longitude: point.longitude,
                altitude: point.altitude,
                timestamp: startedAt.addingTimeInterval(delta * scale),
                horizontalAccuracy: point.horizontalAccuracy
            )
        }
    }

    /// A001 size-parity seed: 2026-11-20 09:33 Asia/Seoul → end 10:23 (elapsed 3000s).
    private static func fixedA001StartedAt() -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 11,
            day: 20,
            hour: 9,
            minute: 33,
            second: 0
        )
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_795_128_780)
    }

    /// Epoch millis aligned with Android `app/src/debug/assets/label-placement/*.json`.
    private static func fixedSeedStartedAt(for fixture: UITestMountainPathFixtures.Fixture) -> Date {
        let millis: Double = {
            switch fixture.id {
            case UITestMountainPathFixtures.gamajicheon.id:
                return 1_794_830_565_217 // 2026-11-16 21:02:45.217 KST → 오후 9:02
            case UITestMountainPathFixtures.saryangdo.id:
                return 1_794_697_200_000 // 2026-11-15 08:00:00 KST
            case UITestMountainPathFixtures.gahyeonsan.id:
                return 1_791_457_128_000 // 2026-10-08 19:58:48 KST
            case UITestMountainPathFixtures.samaksan.id:
                return 1_790_904_736_000 // 2026-10-02 10:32:16 KST
            default:
                return 1_794_830_565_217
            }
        }()
        return Date(timeIntervalSince1970: millis / 1000.0)
    }

    /// `SANSAN_EXPORT_SUMMARIES=1` → Documents/label-placement/ios-summary-*.png
    private static func exportSummariesIfNeeded() {
        let env = ProcessInfo.processInfo.environment["SANSAN_EXPORT_SUMMARIES"]
        let arg = ProcessInfo.processInfo.arguments.contains("-SANSAN_EXPORT_SUMMARIES")
        guard env == "1" || arg else { return }
        Task { @MainActor in
            // Wait for summaryImageRenderer wiring + seed rename.
            try? await Task.sleep(for: .seconds(2))
            let store = HikingRecordStore.shared
            store.reloadForCurrentUser()
            let dir = UserDataPaths.documentsDirectory
                .appendingPathComponent("label-placement", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Parity with Android label-placement JSON (weather=null) + prior compare: no weather chip.
            // Seoul-epoch seeds can fetch Open-Meteo after save; export forces weather off.
            let exportMapOptions = HikingShareMapExportOptions(
                showsDistanceMarkers: true,
                showsTimeMarkers: true,
                showsWeatherLabel: false,
                showsPhotoMarkers: true,
                showsPinnedThumbnails: false
            )

            let map: [(String, UUID)] = [
                ("saryangdo", saryangdoSeedID),
                ("gahyeonsan", gahyeonsanSeedID),
                ("samaksan", samaksanSeedID),
                ("gamajicheon", gamajicheonSeedID),
            ]
            for (name, id) in map {
                guard let record = store.records.first(where: { $0.id == id }) else {
                    print("[km-label] summary export missing seed \(name)")
                    continue
                }
                // Force summary style renderer path.
                let previous = HikingRecordImageSavePreferences.style
                HikingRecordImageSavePreferences.style = .summary
                defer { HikingRecordImageSavePreferences.style = previous }
                guard let image = await store.shareImage(for: id, mapOptions: exportMapOptions) else {
                    print("[km-label] summary export render failed \(name) title=\(record.displayName ?? "?")")
                    continue
                }
                let url = dir.appendingPathComponent("ios-summary-\(name).png")
                if let data = image.pngData() {
                    try? data.write(to: url, options: .atomic)
                    print("[km-label] wrote \(url.lastPathComponent) title=\(record.displayName ?? "") dist=\(Int(record.session.totalDistance))m")
                }
            }

            // 가마지천: 메모없음 / 메모있음 (경로 fit top = title bottom + clearance, Android 동일).
            let gamaID = gamajicheonSeedID
            if store.records.contains(where: { $0.id == gamaID }) {
                let previous = HikingRecordImageSavePreferences.style
                HikingRecordImageSavePreferences.style = .summary
                defer { HikingRecordImageSavePreferences.style = previous }

                store.updateMemo(id: gamaID, memo: "")
                if let image = await store.shareImage(for: gamaID, mapOptions: exportMapOptions),
                   let data = image.pngData() {
                    let url = dir.appendingPathComponent("ios-summary-gamajicheon-memo-none.png")
                    try? data.write(to: url, options: .atomic)
                    print("[km-label] wrote \(url.lastPathComponent)")
                }

                store.updateMemo(id: gamaID, memo: "가마지천 따라 한 바퀴. 저녁 산책.")
                if let image = await store.shareImage(for: gamaID, mapOptions: exportMapOptions),
                   let data = image.pngData() {
                    let url = dir.appendingPathComponent("ios-summary-gamajicheon-memo-on.png")
                    try? data.write(to: url, options: .atomic)
                    print("[km-label] wrote \(url.lastPathComponent)")
                }
                // Leave memo cleared so default gamajicheon summary stays memo-none.
                store.updateMemo(id: gamaID, memo: "")
            }
            // Signal done
            let done = dir.appendingPathComponent("SUMMARIES_DONE.txt")
            try? "ok\n".write(to: done, atomically: true, encoding: .utf8)
        }
    }

    /// `SANSAN_EXPORT_SAVE_STYLES=1` → Documents/image-save-style-pager/*.png
    /// Three save styles for 가마지천 + settings pager page stills.
    private static func exportSaveStylesIfNeeded() {
        let env = ProcessInfo.processInfo.environment["SANSAN_EXPORT_SAVE_STYLES"]
        let arg = ProcessInfo.processInfo.arguments.contains("-SANSAN_EXPORT_SAVE_STYLES")
        guard env == "1" || arg else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            let store = HikingRecordStore.shared
            store.reloadForCurrentUser()
            let dir = UserDataPaths.documentsDirectory
                .appendingPathComponent("image-save-style-pager", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let exportMapOptions = HikingShareMapExportOptions(
                showsDistanceMarkers: true,
                showsTimeMarkers: true,
                showsWeatherLabel: false,
                showsPhotoMarkers: true,
                showsPinnedThumbnails: false
            )

            let styles: [(HikingRecordImageSaveStyle, String)] = [
                (.card, "data-card"),
                (.summary, "simple-grey"),
                (.simpleColor, "simple-color"),
            ]
            let previous = HikingRecordImageSavePreferences.style
            defer { HikingRecordImageSavePreferences.style = previous }

            /// Export both when present: hangjunaru = pager SoT; gamajicheon = label-size SoT.
            let hangju = store.records.first(where: {
                $0.id == hangjunaruSeedID || ($0.displayName ?? "").contains("행주나루")
            })
            let gamaID = gamajicheonSeedID
            let gama = store.records.first(where: { $0.id == gamaID })
            var exportTargets: [(UUID, String)] = []
            if let hangju { exportTargets.append((hangju.id, "hangjunaru")) }
            if let gama { exportTargets.append((gama.id, "gamajicheon")) }
            if exportTargets.isEmpty {
                print("[save-style] missing hangjunaru + gamajicheon")
                return
            }
            for (recordID, hikeSlug) in exportTargets {
                if recordID == gamaID {
                    store.updateMemo(id: gamaID, memo: "")
                }
                guard let record = store.records.first(where: { $0.id == recordID }) else { continue }
                let kmLabels = HikingSessionMetrics.kilometerArrivalElapsedLabels(
                    from: record.session.points,
                    startedAt: record.session.startedAt,
                    segmentBreaks: record.session.segmentBreaks
                )
                print(
                    "[save-style] \(hikeSlug) dist=\(String(format: "%.2f", record.session.totalDistance / 1000))km "
                        + "name=\(record.displayName ?? "?") 4km=\(kmLabels[4] ?? "?")"
                )
                for (style, slug) in styles {
                    HikingRecordImageSavePreferences.style = style
                    guard let image = await store.shareImage(
                        for: recordID,
                        mapOptions: exportMapOptions,
                        fullScreen: true
                    ), let data = image.pngData() else {
                        print("[save-style] render failed \(hikeSlug)-\(slug)")
                        continue
                    }
                    let url = dir.appendingPathComponent("ios-\(hikeSlug)-\(slug).png")
                    try? data.write(to: url, options: .atomic)
                    print("[save-style] wrote \(url.lastPathComponent) \(Int(image.size.width))×\(Int(image.size.height))@\(Int(image.scale))")
                }
            }

            // Settings pager page stills (illustrative previews).
            for style in HikingRecordImageSaveStyle.pagerOrder {
                let preview = ImageSaveStylePageExportPreview(style: style)
                    .frame(width: 320, height: 220)
                let renderer = ImageRenderer(content: preview)
                renderer.proposedSize = ProposedViewSize(width: 320, height: 220)
                renderer.scale = 3
                if let image = renderer.uiImage, let data = image.pngData() {
                    let slug = style.rawValue
                    let url = dir.appendingPathComponent("settings-page-\(slug).png")
                    try? data.write(to: url, options: .atomic)
                    print("[save-style] wrote \(url.lastPathComponent)")
                }
            }

            let done = dir.appendingPathComponent("SAVE_STYLES_DONE.txt")
            try? "ok\n".write(to: done, atomically: true, encoding: .utf8)
        }
    }

    /// `SANSAN_EXPORT_PHOTO_OFF=1` → Documents/image-save-style-pager/photo-off/*
    /// Record with trail photo + map pin; save PNG must omit photo markers/thumbnails.
    private static func exportPhotoOffEvidenceIfNeeded() {
        let env = ProcessInfo.processInfo.environment["SANSAN_EXPORT_PHOTO_OFF"]
        let arg = ProcessInfo.processInfo.arguments.contains("-SANSAN_EXPORT_PHOTO_OFF")
        guard env == "1" || arg else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.8))
            let store = HikingRecordStore.shared
            store.reloadForCurrentUser()
            let dir = UserDataPaths.documentsDirectory
                .appendingPathComponent("image-save-style-pager/photo-off", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let recordID = seedSessionID
            guard var record = store.records.first(where: { $0.id == recordID }),
                  let photo = record.session.photos.first else {
                print("[photo-off] missing seeded record with photo")
                return
            }
            _ = store.pinMapPhoto(recordID: recordID, photoID: photo.id)
            record = store.records.first(where: { $0.id == recordID }) ?? record
            print("[photo-off] photos=\(record.session.photos.count) pinned=\(record.mapPinnedPhotoIDs.count)")

            // Explicit true would have drawn markers; feature flags must force them off.
            let tryOnOptions = HikingShareMapExportOptions(
                showsDistanceMarkers: true,
                showsTimeMarkers: true,
                showsWeatherLabel: false,
                showsPhotoMarkers: true,
                showsPinnedThumbnails: true
            )
            let previous = HikingRecordImageSavePreferences.style
            defer { HikingRecordImageSavePreferences.style = previous }

            for (style, slug) in [
                (HikingRecordImageSaveStyle.card, "data-card"),
                (.simpleColor, "simple-color"),
            ] as [(HikingRecordImageSaveStyle, String)] {
                HikingRecordImageSavePreferences.style = style
                guard let image = await store.shareImage(
                    for: recordID,
                    mapOptions: tryOnOptions,
                    fullScreen: true
                ), let data = image.pngData() else {
                    print("[photo-off] render failed \(slug)")
                    continue
                }
                let url = dir.appendingPathComponent("ios-photo-record-\(slug).png")
                try? data.write(to: url, options: .atomic)
                print("[photo-off] wrote \(url.lastPathComponent)")
            }

            let done = dir.appendingPathComponent("PHOTO_OFF_DONE.txt")
            try? "ok\nphotos=\(record.session.photos.count) pinned=\(record.mapPinnedPhotoIDs.count)\n"
                .write(to: done, atomically: true, encoding: .utf8)
        }
    }

    private static func syntheticTrailImage() -> UIImage {
        let size = CGSize(width: 640, height: 480)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(red: 70 / 255, green: 140 / 255, blue: 90 / 255, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let text = "UITest seed" as NSString
            text.draw(
                at: CGPoint(x: 40, y: 210),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 42, weight: .semibold),
                    .foregroundColor: UIColor.white,
                ]
            )
        }
    }
}
#else
enum UITestSupport {
    static let skipHealthAuth = false
    static let seedRecords = false
    static func applyIfNeeded() {}
    static var shouldSkipHealthAuthorization: Bool { false }
}
#endif
#endif
