#if os(iOS)
import Foundation
import UIKit
import CoreLocation

#if DEBUG
/// #73 DEBUG 전용. release 빌드에서는 `#else` no-op만 남습니다.
/// 실행 인자: `-UITestSkipHealthAuth` / `-UITestSeedRecords`
enum UITestSupport {
    static let skipHealthAuth = CommandLine.arguments.contains("-UITestSkipHealthAuth")
    static let seedRecords = CommandLine.arguments.contains("-UITestSeedRecords")

    /// 고정 UUID — 재실행 시 동일 시드, 실기록 wipe 금지.
    private static let seedSessionID = UUID(uuidString: "00000000-0000-4000-8000-00000000a001")!
    private static let seedPhotoID = UUID(uuidString: "00000000-0000-4000-8000-00000000b001")!
    /// 가현산급 짧은 기록 (≈4.28km, km 점 1–4) — detail label zoom 검증용.
    private static let shortSeedSessionID = UUID(uuidString: "00000000-0000-4000-8000-00000000a428")!
    /// 사량도급 (~8.2km) — 요약·상세 라벨 배치 검증.
    private static let saryangSeedSessionID = UUID(uuidString: "00000000-0000-4000-8000-00000000a820")!
    /// 삼악산급 (~6.1km).
    private static let samakSeedSessionID = UUID(uuidString: "00000000-0000-4000-8000-00000000a610")!

    static var gahyeonsanSeedID: UUID { shortSeedSessionID }
    static var saryangdoSeedID: UUID { saryangSeedSessionID }
    static var samaksanSeedID: UUID { samakSeedSessionID }

    private static var didSeedPlacementRecords = false

    static func applyIfNeeded() {
        guard seedRecords else { return }
        // Single main-queue pass after user activation (avoid merge-on-resave zigzag).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard UserDataPaths.isUserSelected else { return }
            guard !didSeedPlacementRecords else { return }
            didSeedPlacementRecords = true
            reseedsPlacementRecords()
        }
    }

    private static func reseedsPlacementRecords() {
        let store = HikingRecordStore.shared
        for id in [seedSessionID, shortSeedSessionID, saryangSeedSessionID, samakSeedSessionID] {
            if store.records.contains(where: { $0.id == id }) {
                store.delete(id: id)
            }
        }
        seedDummyRecordIfNeeded()
        seedShortGahyeonsanLikeRecordIfNeeded()
        seedSaryangdoLikeRecordIfNeeded()
        seedSamaksanLikeRecordIfNeeded()
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

    /// ≈4.28km eastbound path → km markers 1–4 for zoom label thinning captures.
    private static func seedShortGahyeonsanLikeRecordIfNeeded() {
        let store = HikingRecordStore.shared
        if store.records.contains(where: { $0.id == shortSeedSessionID }) { return }
        guard UserDataPaths.isUserSelected else { return }

        let started = Date().addingTimeInterval(-7_200)
        // Near 가현산; ~4.28km due east (1° lon ≈ 87.8km at this lat).
        let startLat = 37.6895
        let startLon = 126.9780
        let targetMeters: Double = 4_280
        let metersPerDegLon = 111_320.0 * cos(startLat * .pi / 180.0)
        let endLon = startLon + (targetMeters / metersPerDegLon)
        let pointCount = 120
        var points: [HikingPoint] = []
        for i in 0..<pointCount {
            let t = Double(i) / Double(pointCount - 1)
            let lat = startLat + sin(t * .pi) * 0.001 // gentle arc, stays ~4.3km
            let lon = startLon + (endLon - startLon) * t
            points.append(
                HikingPoint(
                    latitude: lat,
                    longitude: lon,
                    altitude: 180 + t * 40,
                    timestamp: started.addingTimeInterval(t * 5_400)
                )
            )
        }
        var total: Double = 0
        for i in 1..<points.count {
            let a = CLLocation(latitude: points[i - 1].latitude, longitude: points[i - 1].longitude)
            let b = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            total += b.distance(from: a)
        }
        let session = HikingSessionData(
            sessionID: shortSeedSessionID,
            state: .idle,
            startedAt: started,
            totalDistance: total,
            elapsedTime: 5_400,
            currentAltitude: points.last?.altitude ?? 180,
            points: points,
            photos: [],
            stepCount: Int(total / 0.7),
            activeEnergyKilocalories: 320,
            elevationGainMeters: 90
        )
        store.save(session)
        store.renameRecord(id: shortSeedSessionID, title: "가현산(시드 4.28km)")
    }

    private static func seedSaryangdoLikeRecordIfNeeded() {
        seedArcRecordIfNeeded(
            id: saryangSeedSessionID,
            title: "사량도(시드 8.2km)",
            startLat: 34.8410,
            startLon: 128.1980,
            targetMeters: 8_200,
            pointCount: 200,
            latWiggle: 0.0008
        )
    }

    private static func seedSamaksanLikeRecordIfNeeded() {
        seedArcRecordIfNeeded(
            id: samakSeedSessionID,
            title: "삼악산(시드 6.1km)",
            startLat: 37.8780,
            startLon: 127.6950,
            targetMeters: 6_100,
            pointCount: 160,
            latWiggle: 0.0006
        )
    }

    private static func seedArcRecordIfNeeded(
        id: UUID,
        title: String,
        startLat: Double,
        startLon: Double,
        targetMeters: Double,
        pointCount: Int,
        latWiggle: Double
    ) {
        let store = HikingRecordStore.shared
        if store.records.contains(where: { $0.id == id }) { return }
        guard UserDataPaths.isUserSelected else { return }

        let started = Date().addingTimeInterval(-10_800)
        // Build by stepping fixed meters so total ≈ target (avoid lon-degree drift).
        let metersPerDegLat = 110_540.0
        let metersPerDegLon = 111_320.0 * cos(startLat * .pi / 180.0)
        var points: [HikingPoint] = []
        var lat = startLat
        var lon = startLon
        points.append(
            HikingPoint(latitude: lat, longitude: lon, altitude: 50, timestamp: started)
        )
        let step = targetMeters / Double(pointCount - 1)
        for i in 1..<pointCount {
            let t = Double(i) / Double(pointCount - 1)
            lon += step / metersPerDegLon
            lat = startLat + sin(t * .pi) * latWiggle
            points.append(
                HikingPoint(
                    latitude: lat,
                    longitude: lon,
                    altitude: 50 + t * 200,
                    timestamp: started.addingTimeInterval(t * 8_000)
                )
            )
        }
        var total: Double = 0
        for i in 1..<points.count {
            let a = CLLocation(latitude: points[i - 1].latitude, longitude: points[i - 1].longitude)
            let b = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            total += b.distance(from: a)
        }
        _ = metersPerDegLat
        let session = HikingSessionData(
            sessionID: id,
            state: .idle,
            startedAt: started,
            totalDistance: total,
            elapsedTime: 8_000,
            currentAltitude: points.last?.altitude ?? 50,
            points: points,
            photos: [],
            stepCount: Int(total / 0.7),
            activeEnergyKilocalories: total / 15,
            elevationGainMeters: 180
        )
        store.save(session)
        store.renameRecord(id: id, title: title)
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
