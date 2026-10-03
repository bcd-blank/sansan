//
//  HikingRecordStore.swift
//  Shared
//

#if os(iOS)

import Combine
import Foundation
import UIKit

/// 완료된 등산 기록 영구 저장(iPhone).
@MainActor
final class HikingRecordStore: ObservableObject {
    static let shared = HikingRecordStore()

    @Published private(set) var records: [SavedHikingSession] = []
    /// 첫 로드가 끝나기 전에는 follow 복원이 기록을 비어 있다고 보고 지워지지 않게 합니다.
    @Published private(set) var hasCompletedInitialLoad = false
    @Published private(set) var isGeneratingSnapshot = false
    @Published private(set) var regeneratingRecordID: UUID?
    /// 목록 썸네일 갱신용 — PNG 경로가 같아도 재로드되도록 합니다.
    @Published private(set) var snapshotRevisions: [UUID: UInt] = [:]
    /// `persist()` 실패 시 사용자 알림용.
    @Published private(set) var persistFailure: RecordPersistFailure?

    private var fileURL: URL { UserDataPaths.recordsFileURL }

    private struct RouteImageCacheEntry {
        let mapOptions: HikingShareMapExportOptions
        let fullScreen: Bool
        let image: UIImage
    }

    private var routeImageCache: [UUID: RouteImageCacheEntry] = [:]

    private init() {
        Self.installWorkoutArchiveHandlerIfNeeded()
    }

    func reloadForCurrentUser() {
        guard UserDataPaths.isUserSelected else {
            records = []
            hasCompletedInitialLoad = true
            return
        }
        syncPreferenceObservers()
        load()
        HikingRouteFollowObserver.shared.syncFromStorage()
    }

    /// 메인 화면이 떠 있는 동안 JSON 디코드로 버튼을 막지 않습니다.
    func reloadForCurrentUserOffMain() async {
        guard UserDataPaths.isUserSelected else {
            records = []
            hasCompletedInitialLoad = true
            return
        }
        syncPreferenceObservers()
        await loadOffMain()
        HikingRouteFollowObserver.shared.syncFromStorage()
    }

    private func syncPreferenceObservers() {
        HikingSnapshotPreferencesObserver.shared.syncFromStorage()
        HikingShareExportPreferencesObserver.shared.syncFromStorage()
        UserProfilePhotoObserver.shared.syncFromStorage()
    }

    func clearForSignOut() {
        records = []
        hasCompletedInitialLoad = false
        isGeneratingSnapshot = false
        regeneratingRecordID = nil
        snapshotRevisions.removeAll()
        routeImageCache.removeAll()
        HikingRouteFollowObserver.shared.clearFollowedRoute()
        UserProfilePhotoObserver.shared.clearForSignOut()
    }

    func snapshotRevision(for recordID: UUID) -> UInt {
        snapshotRevisions[recordID, default: 0]
    }

    func clearRouteImageCache(for recordID: UUID) {
        routeImageCache.removeValue(forKey: recordID)
    }

    func clearAllRouteImageCaches() {
        routeImageCache.removeAll()
    }

    func dismissPersistFailure() {
        persistFailure = nil
    }

    func retryPersist() {
        persist()
    }

    private func invalidateRouteImageCache(for recordID: UUID) {
        clearRouteImageCache(for: recordID)
    }

    private func bumpSnapshotRevision(for recordID: UUID) {
        snapshotRevisions[recordID, default: 0] += 1
    }

    /// 공유·저장 이미지 — 상세 화면과 동일한 SwiftUI 레이아웃으로 렌더링(sansan 앱에서 등록).
    /// `fullScreen`이 true이면 기기 화면 전체 크기로 렌더링(사진 저장용).
    static var shareImageRenderer: (@MainActor (SavedHikingSession, UIImage, Bool) -> UIImage?)?

    /// 사진 저장용 — 기록 상세 지도와 동일한 pt·배율(sansan 앱에서 등록).
    static var detailShareMapCanvasProvider: (@MainActor () -> (size: CGSize, pixelScale: CGFloat))?

    /// `WorkoutManager` ↔ 저장소 연결 (Shared·Watch/iOS 타겟 분리용).
    private static var didInstallWorkoutArchiveHandler = false

    private static func installWorkoutArchiveHandlerIfNeeded() {
        guard !didInstallWorkoutArchiveHandler else { return }
        didInstallWorkoutArchiveHandler = true
        WorkoutManager.sessionArchiveHandler = { session in
            HikingRecordStore.shared.save(session)
        }
    }

    func save(_ session: HikingSessionData) {
        guard UserDataPaths.isUserSelected else { return }

        // 동일 세션이 이미 저장돼 있으면(예: 잘린 스냅샷 선도착 후 전체 파일 도착) 합집합 병합합니다.
        if let existing = records.first(where: { $0.id == session.sessionID }) {
            var merged = existing.session.mergingSameSession(with: session)
            merged.finalizeForPersistence()
            guard shouldPersist(merged) else { return }
            insertSavedRecord(existing.withSession(merged, endedAt: merged.effectiveEndedAt))
            return
        }

        var finalized = session
        finalized.finalizeForPersistence()
        guard shouldPersist(finalized) else { return }

        let saved = SavedHikingSession(session: finalized, endedAt: finalized.effectiveEndedAt)
        insertSavedRecord(saved)
    }

    @discardableResult
    func importGPX(from url: URL) async -> Result<UUID, HikingGPXImporter.ImportError> {
        guard UserDataPaths.isUserSelected else {
            return .failure(.noUser)
        }

        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let parsed: HikingGPXImporter.ParsedTrack
        do {
            parsed = try HikingGPXImporter.parse(url: url)
        } catch let error as HikingGPXImporter.ImportError {
            return .failure(error)
        } catch {
            return .failure(.unreadableFile)
        }

        let saved = SavedHikingSession(
            session: parsed.sessionData,
            endedAt: parsed.endedAt,
            displayName: parsed.displayName,
            importSource: .gpx
        )
        insertSavedRecord(saved)
        return .success(saved.id)
    }

#if os(iOS)
    @discardableResult
    func importKMSCCourse(_ entry: KMSCCourseEntry) async -> Result<UUID, KMSCCourseImportError> {
        guard UserDataPaths.isUserSelected else {
            return .failure(.noUser)
        }

        if let existing = records.first(where: { $0.bundledRouteID == entry.id }) {
            return .success(existing.id)
        }

        let parsed: HikingGPXImporter.ParsedTrack
        do {
            parsed = try await KMSCCourseCatalog.parseCourse(entry)
        } catch let error as KMSCCourseImportError {
            return .failure(error)
        } catch {
            return .failure(.unreadable)
        }

        let saved = SavedHikingSession(
            session: parsed.sessionData,
            endedAt: parsed.endedAt,
            displayName: entry.title,
            importSource: .bundledCatalog,
            bundledRouteID: entry.id
        )
        insertSavedRecord(saved)
        return .success(saved.id)
    }

    func recordID(forBundledRouteID routeID: String) -> UUID? {
        records.first(where: { $0.bundledRouteID == routeID })?.id
    }
#endif

    private func insertSavedRecord(_ saved: SavedHikingSession) {
        records.removeAll { $0.id == saved.id }
        records.insert(saved, at: 0)
        records.sort { $0.endedAt > $1.endedAt }
        persist()

        Task {
            await generateAndAttachSnapshot(for: saved.id)
            await attachWeatherIfNeeded(for: saved.id)
        }
    }

    /// 산행 시작~종료 구간의 날씨 스냅샷을 채웁니다. 없거나 구 기록(평균만 있음)이면 다시 받습니다.
    func attachWeatherIfNeeded(for recordID: UUID) async {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        let existing = records[index].weather
        let needsFetch = existing == nil || existing?.needsWeatherRefresh == true
        guard needsFetch else { return }
        guard
            let coordinate = records[index].routeStartCoordinate,
            let startedAt = records[index].startedAt
        else {
            return
        }
        let endedAt = records[index].endedAt

        guard let snapshot = await HikingRouteWeatherService.fetch(
            coordinate: coordinate,
            from: startedAt,
            to: endedAt
        ) else {
            return
        }

        guard let refreshedIndex = records.firstIndex(where: { $0.id == recordID }) else {
            return
        }
        if let current = records[refreshedIndex].weather, !current.needsWeatherRefresh {
            return
        }

        records[refreshedIndex].weather = snapshot
        persist()
        invalidateRouteImageCache(for: recordID)
    }

    func delete(at offsets: IndexSet) {
        let removed = offsets.map { records[$0] }
        for index in offsets.sorted(by: >) {
            guard records.indices.contains(index) else { continue }
            records.remove(at: index)
        }
        removed.forEach { record in
            HikingRouteFollowObserver.shared.clearIfFollowing(recordID: record.id)
            deleteAssets(for: record)
        }
        HikingRecordTombstoneStore.append(ids: removed.map(\.id))
        persist()
    }

    func delete(id: UUID) {
        if let record = records.first(where: { $0.id == id }) {
            HikingRouteFollowObserver.shared.clearIfFollowing(recordID: record.id)
            deleteAssets(for: record)
            HikingRecordTombstoneStore.append(ids: [record.id])
        }
        records.removeAll { $0.id == id }
        persist()
    }

    func renameRecord(id: UUID, title: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].displayName = SavedHikingSession.normalizedDisplayName(title)
        persist()
    }

    func updateMemo(id: UUID, memo: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].memo = SavedHikingSession.normalizedMemo(memo)
        persist()
    }

    func toggleListPinned(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].isListPinned.toggle()
        if records[index].isListPinned {
            records[index].listPinnedAt = Date()
        } else {
            records[index].listPinnedAt = nil
        }
        persist()
    }

    func toggleFavorite(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].isFavorite.toggle()
        if records[index].isFavorite {
            records[index].favoritedAt = Date()
        } else {
            records[index].favoritedAt = nil
        }
        persist()
    }

    enum MapPhotoPinResult: Equatable {
        case pinned
        case alreadyPinned
        case limitReached
        case notFound
    }

    /// 지도 상단 썸네일 고정 (최대 5개).
    func pinMapPhoto(recordID: UUID, photoID: UUID) -> MapPhotoPinResult {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return .notFound }
        guard records[index].session.photos.contains(where: { $0.id == photoID }) else { return .notFound }
        if records[index].mapPinnedPhotoIDs.contains(photoID) { return .alreadyPinned }
        if records[index].mapPinnedPhotoIDs.count >= SavedHikingSession.maxMapPinnedPhotos {
            return .limitReached
        }
        records[index].mapPinnedPhotoIDs.append(photoID)
        persist()
        return .pinned
    }

    func unpinMapPhoto(recordID: UUID, photoID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].mapPinnedPhotoIDs.removeAll { $0 == photoID }
        persist()
    }

    private func pruneMapPinnedPhotos(at index: Int) {
        let validIDs = Set(records[index].session.photos.map(\.id))
        records[index].mapPinnedPhotoIDs.removeAll { !validIDs.contains($0) }
    }

    /// 기록에서 트레일 사진 1장을 제거하고 경로 스냅샷을 다시 생성합니다.
    @discardableResult
    func deleteTrailPhoto(recordID: UUID, photoID: UUID) async -> Bool {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return false }
        guard let photo = records[index].session.photos.first(where: { $0.id == photoID }) else {
            return false
        }

        HikingTrailPhotoStore.deletePhoto(sessionID: recordID, filename: photo.filename)

        var session = records[index].session
        session.photos.removeAll { $0.id == photoID }
        let existing = records[index]
        var pinnedIDs = existing.mapPinnedPhotoIDs
        pinnedIDs.removeAll { $0 == photoID }
        records[index] = SavedHikingSession(
            session: session,
            endedAt: existing.endedAt,
            snapshotFilename: existing.snapshotFilename,
            mapPinnedPhotoIDs: pinnedIDs,
            displayName: existing.displayName,
            memo: existing.memo,
            weather: existing.weather
        )
        persist()

        if records[index].session.points.count >= 2 {
            await generateAndAttachSnapshot(for: recordID)
        }
        return true
    }

    func regenerateAllSnapshots() async {
        let targets = records.filter { $0.session.points.count >= 2 }
        guard !targets.isEmpty else { return }

        isGeneratingSnapshot = true
        defer {
            isGeneratingSnapshot = false
            regeneratingRecordID = nil
        }

        for record in targets {
            await generateAndAttachSnapshot(for: record.id, tracksGlobalProgress: false)
        }
    }

    func generateAndAttachSnapshot(for recordID: UUID) async {
        await generateAndAttachSnapshot(for: recordID, tracksGlobalProgress: true)
    }

    private func generateAndAttachSnapshot(for recordID: UUID, tracksGlobalProgress: Bool) async {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        let record = records[index]
        guard record.session.points.count >= 2 else { return }

        if tracksGlobalProgress {
            isGeneratingSnapshot = true
        }
        regeneratingRecordID = recordID
        defer {
            if tracksGlobalProgress {
                isGeneratingSnapshot = false
            }
            if regeneratingRecordID == recordID {
                regeneratingRecordID = nil
            }
        }

        let listThumbnailMapOptions = HikingShareMapExportOptions(
            showsPhotoMarkers: false,
            showsPinnedThumbnails: false
        )

        // 기록 종료 직후에는 요약 화면 닫힘·목록 표시 등 화면 전환과 겹쳐 지도 캡처가
        // 일시적으로 실패할 수 있습니다. 실패 시 화면이 안정된 뒤 재시도합니다.
        var image: UIImage?
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(1.5 * Double(attempt)))
            }
            // 재시도 시점에는 세션 병합 등으로 기록이 갱신됐을 수 있어 매번 다시 읽습니다.
            guard let latestRecord = records.first(where: { $0.id == recordID }) else { return }
            image = await HikingRouteSnapshotGenerator.generate(
                record: latestRecord,
                style: .routeOnly,
                mapOptions: listThumbnailMapOptions,
                allowLiveDetailCapture: false,
                preferSwiftUIMapTiles: true,
                listThumbnailOnly: true
            )
            if image != nil { break }
        }
        guard let image else { return }

        let filename = HikingStorageLayout.snapshotFilename
        guard let root = UserDataPaths.activeUserRoot else { return }
        let directory = HikingStorageLayout.recordDirectory(recordID: record.id, in: root)
        let url = HikingStorageLayout.snapshotURL(recordID: record.id, in: root)

        guard let pngData = image.pngData() else { return }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try pngData.write(to: url, options: [.atomic])
            HikingRecordAssetCleaner.purgeNumberedConflictCopies(of: filename, in: directory)
            // 생성 중 기록이 지워지거나 목록이 갱신됐을 수 있어 인덱스를 다시 찾습니다.
            guard let currentIndex = records.firstIndex(where: { $0.id == recordID }) else { return }
            records[currentIndex].snapshotFilename = filename
            persist()
            bumpSnapshotRevision(for: recordID)
            invalidateRouteImageCache(for: recordID)
        } catch {
            // PNG 저장 실패 시 JSON 기록은 유지.
        }
    }

    /// 목록에 썸네일 PNG가 없는 기록이 보이면 자동 생성합니다(기록 종료 직후 생성 실패 자가 복구).
    private var snapshotEnsureInFlightIDs: Set<UUID> = []

    func ensureSnapshotExists(for recordID: UUID) async {
        guard let record = records.first(where: { $0.id == recordID }) else { return }
        guard record.session.points.count >= 2 else { return }
        if let path = record.snapshotFileURL?.path, FileManager.default.fileExists(atPath: path) {
            return
        }
        guard !snapshotEnsureInFlightIDs.contains(recordID) else { return }
        snapshotEnsureInFlightIDs.insert(recordID)
        defer { snapshotEnsureInFlightIDs.remove(recordID) }
        await generateAndAttachSnapshot(for: recordID, tracksGlobalProgress: false)
    }

    /// 공유·사진 저장용 합성 이미지 (경로 + 기록 요약).
    func shareImage(
        for recordID: UUID,
        mapOptions: HikingShareMapExportOptions = HikingShareExportPreferences.mapOptions,
        fullScreen: Bool = false
    ) async -> UIImage? {
        guard let record = records.first(where: { $0.id == recordID }) else { return nil }
        guard let routeImage = await routeImageForShare(
            record: record,
            mapOptions: mapOptions,
            fullScreen: fullScreen
        ) else { return nil }
        if let renderer = Self.shareImageRenderer {
            return renderer(record, routeImage, fullScreen)
        }
        return nil
    }

    private func routeImage(for record: SavedHikingSession) async -> UIImage? {
        if let url = record.snapshotFileURL,
           let cached = UIImage(contentsOfFile: url.path) {
            return HikingRouteSnapshotGenerator.applyingBrandOverlay(
                to: cached,
                style: HikingSnapshotPreferences.style
            )
        }
        guard let base = await HikingRouteSnapshotGenerator.generate(
            record: record,
            style: .routeOnly
        ) else { return nil }
        return HikingRouteSnapshotGenerator.applyingBrandOverlay(
            to: base,
            style: HikingSnapshotPreferences.style
        )
    }

    /// 공유·사진 저장용 경로 이미지 — 디스크/메모리 캐시 우선, 없을 때만 MKMapView 캡처.
    private func routeImageForShare(
        record: SavedHikingSession,
        mapOptions: HikingShareMapExportOptions,
        fullScreen: Bool
    ) async -> UIImage? {
        if let cached = routeImageCache[record.id],
           cached.mapOptions == mapOptions,
           cached.fullScreen == fullScreen {
            return cached.image
        }

        // 사진 마커·핀 썸네일은 MKMapView 좌표계로만 정확히 맞출 수 있어 캐시 PNG에 덧그리지 않습니다.
        let image: UIImage?
        if !fullScreen,
           let url = record.snapshotFileURL,
           let diskCached = UIImage(contentsOfFile: url.path),
           !HikingRouteSnapshotGenerator.needsShareOverlays(mapOptions, record: record) {
            image = diskCached
        } else {
            let detailCanvas = fullScreen ? Self.detailShareMapCanvasProvider?() : nil
            image = await HikingRouteSnapshotGenerator.generate(
                record: record,
                style: .routeOnly,
                mapOptions: mapOptions,
                canvasSize: detailCanvas?.size,
                pixelScale: detailCanvas?.pixelScale,
                reservesLegalAttributionStrip: true,
                allowLiveDetailCapture: HikingRouteSnapshotGenerator.allowsLiveDetailCapture?(record.id) ?? false
            )
        }

        if let image {
            let exportImage = fullScreen
                ? RouteMapOverlayMetrics.coveringNativeAppleMapsAttribution(on: image)
                : image
            routeImageCache[record.id] = RouteImageCacheEntry(
                mapOptions: mapOptions,
                fullScreen: fullScreen,
                image: exportImage
            )
            return exportImage
        }
        return nil
    }

    private func deleteAssets(for record: SavedHikingSession) {
        guard let root = UserDataPaths.activeUserRoot else { return }
        HikingStorageLayout.removeRecordPackage(recordID: record.id, in: root)
    }

    private func shouldPersist(_ session: HikingSessionData) -> Bool {
        session.elapsedTime > 0
            || session.totalDistance > 0
            || !session.points.isEmpty
            || !session.photos.isEmpty
    }

    private func load() {
        guard let sourceURL = UserDataPaths.existingRecordsFileURL else {
            applyLoaded([])
            return
        }
        guard let loaded = Self.decodeRecords(at: sourceURL, excluding: tombstonedRecordIDs()) else {
            return
        }
        applyLoaded(loaded)
    }

    private func loadOffMain() async {
        guard let url = UserDataPaths.existingRecordsFileURL else {
            applyLoaded([])
            return
        }
        let excluded = tombstonedRecordIDs()
        let loaded = await Task.detached(priority: .userInitiated) {
            Self.decodeRecords(at: url, excluding: excluded)
        }.value
        guard let loaded else { return }
        applyLoaded(loaded)
    }

    private func applyLoaded(_ loaded: [SavedHikingSession]) {
        let pending = records
        if pending.isEmpty {
            records = loaded
        } else {
            records = merging(pending, onto: loaded)
        }
        hasCompletedInitialLoad = true
        if !pending.isEmpty {
            persist()
        }
        scheduleDisplayCacheBackfillIfNeeded()
        scheduleStorageMaintenance()
    }

    private func scheduleStorageMaintenance() {
        guard let root = UserDataPaths.activeUserRoot else { return }
        let recordIDs = Set(records.map(\.id))
        var photoIDsByRecord: [UUID: Set<UUID>] = [:]
        for record in records {
            photoIDsByRecord[record.id] = Set(record.session.photos.map(\.id))
        }
        var extraProtectedIDs = Set<UUID>()
        let live = WorkoutManager.shared.sessionData
        if live.state == .recording || live.state == .paused {
            extraProtectedIDs.insert(live.sessionID)
        }
        let shouldDeleteOrphans = !recordIDs.isEmpty || !tombstonedRecordIDs().isEmpty
        Task.detached(priority: .utility) {
            HikingStorageMaintenance.run(
                at: root,
                recordIDs: recordIDs,
                photoIDsByRecord: photoIDsByRecord,
                extraProtectedIDs: extraProtectedIDs,
                deleteOrphans: shouldDeleteOrphans
            )
        }
    }

    private func tombstonedRecordIDs() -> Set<UUID> {
        Set(HikingRecordTombstoneStore.load().map(\.id))
    }

    /// 디스크 로드 전에 저장된 워치·아이폰 기록을 기존 목록과 합칩니다.
    private func merging(
        _ pending: [SavedHikingSession],
        onto loaded: [SavedHikingSession]
    ) -> [SavedHikingSession] {
        var byID: [UUID: SavedHikingSession] = [:]
        for record in loaded {
            byID[record.id] = record
        }
        for record in pending {
            if let existing = byID[record.id] {
                let mergedSession = existing.session.mergingSameSession(with: record.session)
                byID[record.id] = existing.withSession(
                    mergedSession,
                    endedAt: max(existing.endedAt, record.endedAt)
                )
            } else {
                byID[record.id] = record
            }
        }
        return byID.values.sorted { $0.endedAt > $1.endedAt }
    }

    nonisolated private static func decodeRecords(
        at url: URL,
        excluding tombstonedIDs: Set<UUID>
    ) -> [SavedHikingSession]? {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var loaded = try decoder.decode([SavedHikingSession].self, from: data)
            for idx in loaded.indices {
                let valid = Set(loaded[idx].session.photos.map(\.id))
                loaded[idx].mapPinnedPhotoIDs.removeAll { !valid.contains($0) }
            }
            return loaded
                .filter { !tombstonedIDs.contains($0.id) }
                .sorted { $0.endedAt > $1.endedAt }
        } catch {
            return nil
        }
    }

    /// 구버전 기록의 표시용 캐시를 백그라운드에서 한 번 계산해 이후에는 불러오기만 합니다.
    private func scheduleDisplayCacheBackfillIfNeeded() {
        let pending: [(UUID, [HikingPoint], [HikingHeartRateSample])] = records.compactMap { record in
            guard !record.session.hasPersistedDisplayCache,
                  record.session.points.count >= 2 else { return nil }
            return (record.id, record.session.points, record.session.heartRateSamples)
        }
        guard !pending.isEmpty else { return }

        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(2))
            await MountainSummitCatalog.waitUntilReady()
            let computed = pending.map { id, points, heartRateSamples in
                (
                    id,
                    HikingSessionDisplayCacheBuilder.build(
                        points: points,
                        heartRateSamples: heartRateSamples
                    ),
                    HikingSessionMetrics.horizontalDistance(from: points)
                )
            }
            await MainActor.run {
                var changed = false
                for (id, built, recomputedDistance) in computed {
                    guard let index = self.records.firstIndex(where: { $0.id == id }) else { continue }
                    guard !self.records[index].session.hasPersistedDisplayCache else { continue }
                    var record = self.records[index].withDisplayCache(built)
                    // 과거 거리 계산 버그(2m 미만 구간 유실)로 작게 저장된 거리를 보정합니다.
                    if recomputedDistance > record.session.totalDistance {
                        var updatedSession = record.session
                        updatedSession.totalDistance = recomputedDistance
                        record = record.withSession(updatedSession)
                    }
                    self.records[index] = record
                    changed = true
                }
                if changed {
                    Task { await self.persistOffMain() }
                }
            }
        }
    }

    @discardableResult
    private func persist() -> Bool {
        guard hasCompletedInitialLoad else { return false }
        Task { await persistOffMain() }
        return true
    }

    @discardableResult
    private func persistOffMain() async -> Bool {
        guard hasCompletedInitialLoad else { return false }
        let snapshot = records
        let url = fileURL
        do {
            try await Task.detached(priority: .utility) {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: [.atomic])
                if let root = UserDataPaths.activeUserRoot {
                    HikingStorageMigrator.removeLegacyJSONFiles(at: root)
                }
            }.value
            if records != snapshot {
                return await persistOffMain()
            }
            ICloudRecordSync.shared.schedulePush()
            persistFailure = nil
            return true
        } catch {
            persistFailure = RecordPersistFailure(message: Self.persistFailureMessage)
            return false
        }
    }

    private static let persistFailureMessage =
        "등산 기록을 이 기기에 저장하지 못했습니다. 저장 공간을 확인한 뒤 다시 시도해 주세요."
}

struct RecordPersistFailure: Equatable {
    let message: String
}

#endif
