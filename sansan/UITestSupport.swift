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

    private static var didSeedPlacementRecords = false

    static func applyIfNeeded() {
        UITestMapCaptureHooks.installIfNeeded()
        guard seedRecords else { return }
        // Single main-queue pass after user activation (avoid merge-on-resave zigzag).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard UserDataPaths.isUserSelected else { return }
            guard !didSeedPlacementRecords else { return }
            didSeedPlacementRecords = true
            reseedsPlacementRecords()
            exportSummariesIfNeeded()
            exportSaveStylesIfNeeded()
            exportPhotoOffEvidenceIfNeeded()
        }
    }

    private static func reseedsPlacementRecords() {
        let store = HikingRecordStore.shared
        let ids = UITestMountainPathFixtures.all.map(\.id) + [seedSessionID]
        for id in ids {
            if store.records.contains(where: { $0.id == id }) {
                store.delete(id: id)
            }
        }
        seedDummyRecordIfNeeded()
        for fixture in UITestMountainPathFixtures.all {
            seedFixture(fixture)
        }
    }

    static var shouldSkipHealthAuthorization: Bool { skipHealthAuth }

    private static func seedDummyRecordIfNeeded() {
        let store = HikingRecordStore.shared
        if store.records.contains(where: { $0.id == seedSessionID }) { return }
        guard UserDataPaths.isUserSelected else { return }

        let started = Date().addingTimeInterval(-3_600)
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
        let session = HikingSessionData(
            sessionID: fixture.id,
            state: .idle,
            startedAt: started,
            totalDistance: max(measured, fixture.totalDistance * 0.98),
            elapsedTime: fixture.elapsedTime,
            currentAltitude: points.last?.altitude ?? 0,
            points: points,
            photos: [],
            stepCount: fixture.stepCount > 0 ? fixture.stepCount : Int(measured / 0.7),
            activeEnergyKilocalories: fixture.activeEnergyKilocalories,
            elevationGainMeters: fixture.elevationGainMeters
        )
        store.save(session)
        store.renameRecord(id: fixture.id, title: fixture.title)
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

            let gamaID = gamajicheonSeedID
            guard store.records.contains(where: { $0.id == gamaID }) else {
                print("[save-style] missing gamajicheon seed")
                return
            }
            store.updateMemo(id: gamaID, memo: "")

            let styles: [(HikingRecordImageSaveStyle, String)] = [
                (.card, "data-card"),
                (.summary, "simple-grey"),
                (.simpleColor, "simple-color"),
            ]
            let previous = HikingRecordImageSavePreferences.style
            defer { HikingRecordImageSavePreferences.style = previous }

            for (style, slug) in styles {
                HikingRecordImageSavePreferences.style = style
                guard let image = await store.shareImage(
                    for: gamaID,
                    mapOptions: exportMapOptions,
                    fullScreen: true
                ), let data = image.pngData() else {
                    print("[save-style] render failed \(slug)")
                    continue
                }
                let url = dir.appendingPathComponent("ios-gamajicheon-\(slug).png")
                try? data.write(to: url, options: .atomic)
                print("[save-style] wrote \(url.lastPathComponent) \(Int(image.size.width))×\(Int(image.size.height))@\(Int(image.scale))")
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
