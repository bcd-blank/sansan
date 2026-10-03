//
//  SavedHikingSession.swift
//  Shared
//

import CoreLocation
import Foundation

nonisolated enum HikingRecordImportSource: String, Codable, Hashable, Sendable {
    case gpx
    case bundledCatalog
}

/// 완료된 등산 기록(영구 저장용).
nonisolated struct SavedHikingSession: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let endedAt: Date
    let session: HikingSessionData
    /// 목록 썸네일 파일명. 현재 레이아웃에서는 항상 `snapshot.png`.
    var snapshotFilename: String?
    /// 지도 상단에 고정할 사진 ID (최대 5개, 순서 유지).
    var mapPinnedPhotoIDs: [UUID]
    /// 목록 표시 이름. nil 이면 시작·종료 시각 기본값.
    var displayName: String?
    /// 타이틀 카드 제목 아래 사용자 메모.
    var memo: String?
    /// 산행 시작~종료 구간의 대표 날씨 (저장 후 비동기 채움).
    var weather: HikingRouteWeatherSnapshot?
    /// GPX 등 외부에서 가져온 기록이면 출처.
    var importSource: HikingRecordImportSource?
    /// 앱 번들 공공 코스에서 추가한 경우 manifest route id.
    var bundledRouteID: String?
    /// 기록 목록 상단 고정.
    var isListPinned: Bool
    /// 상단 고정한 시각(고정 순서 정렬용).
    var listPinnedAt: Date?
    /// 기록 목록 즐겨찾기.
    var isFavorite: Bool
    /// 즐겨찾기한 시각(즐겨찾기 순서 정렬용).
    var favoritedAt: Date?

    init(
        session: HikingSessionData,
        endedAt: Date = Date(),
        snapshotFilename: String? = nil,
        mapPinnedPhotoIDs: [UUID] = [],
        displayName: String? = nil,
        memo: String? = nil,
        weather: HikingRouteWeatherSnapshot? = nil,
        importSource: HikingRecordImportSource? = nil,
        bundledRouteID: String? = nil,
        isListPinned: Bool = false,
        listPinnedAt: Date? = nil,
        isFavorite: Bool = false,
        favoritedAt: Date? = nil
    ) {
        id = session.sessionID
        self.endedAt = endedAt
        self.snapshotFilename = snapshotFilename
        self.mapPinnedPhotoIDs = Array(mapPinnedPhotoIDs.prefix(SavedHikingSession.maxMapPinnedPhotos))
        self.displayName = Self.normalizedDisplayName(displayName)
        self.memo = Self.normalizedMemo(memo)
        self.weather = weather
        self.importSource = importSource
        self.bundledRouteID = bundledRouteID
        self.isListPinned = isListPinned
        self.listPinnedAt = listPinnedAt
        self.isFavorite = isFavorite
        self.favoritedAt = favoritedAt
        var archived = session
        archived.state = .idle
        self.session = archived
    }

    static let maxMapPinnedPhotos = 5
    static let maxMemoLength = 200

    enum CodingKeys: String, CodingKey {
        case id, endedAt, session, snapshotFilename, mapPinnedPhotoIDs, displayName, memo, weather
        case importSource, bundledRouteID, isListPinned, listPinnedAt, isFavorite, favoritedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        session = try container.decode(HikingSessionData.self, forKey: .session)
        snapshotFilename = try container.decodeIfPresent(String.self, forKey: .snapshotFilename)
        let pinned = try container.decodeIfPresent([UUID].self, forKey: .mapPinnedPhotoIDs) ?? []
        mapPinnedPhotoIDs = Array(pinned.prefix(Self.maxMapPinnedPhotos))
        displayName = Self.normalizedDisplayName(
            try container.decodeIfPresent(String.self, forKey: .displayName)
        )
        memo = Self.normalizedMemo(
            try container.decodeIfPresent(String.self, forKey: .memo)
        )
        weather = try container.decodeIfPresent(HikingRouteWeatherSnapshot.self, forKey: .weather)
        importSource = try container.decodeIfPresent(HikingRecordImportSource.self, forKey: .importSource)
        bundledRouteID = try container.decodeIfPresent(String.self, forKey: .bundledRouteID)
        isListPinned = try container.decodeIfPresent(Bool.self, forKey: .isListPinned) ?? false
        listPinnedAt = try container.decodeIfPresent(Date.self, forKey: .listPinnedAt)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        favoritedAt = try container.decodeIfPresent(Date.self, forKey: .favoritedAt)
        if isListPinned, listPinnedAt == nil {
            listPinnedAt = endedAt
        }
        if isFavorite, favoritedAt == nil {
            favoritedAt = endedAt
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encode(session, forKey: .session)
        try container.encodeIfPresent(snapshotFilename, forKey: .snapshotFilename)
        try container.encode(mapPinnedPhotoIDs, forKey: .mapPinnedPhotoIDs)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(memo, forKey: .memo)
        try container.encodeIfPresent(weather, forKey: .weather)
        try container.encodeIfPresent(importSource, forKey: .importSource)
        try container.encodeIfPresent(bundledRouteID, forKey: .bundledRouteID)
        try container.encode(isListPinned, forKey: .isListPinned)
        try container.encodeIfPresent(listPinnedAt, forKey: .listPinnedAt)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encodeIfPresent(favoritedAt, forKey: .favoritedAt)
    }

    var isImported: Bool { importSource != nil }

    func withDisplayCache(_ built: HikingSessionDisplayCacheBuilder.Built) -> SavedHikingSession {
        var updatedSession = session
        updatedSession.applyDisplayCache(built)
        return withSession(updatedSession)
    }

    /// 사용자 메타데이터(이름·메모·핀 등)는 유지하고 세션 데이터만 교체합니다.
    func withSession(_ newSession: HikingSessionData, endedAt: Date? = nil) -> SavedHikingSession {
        SavedHikingSession(
            session: newSession,
            endedAt: endedAt ?? self.endedAt,
            snapshotFilename: snapshotFilename,
            mapPinnedPhotoIDs: mapPinnedPhotoIDs,
            displayName: displayName,
            memo: memo,
            weather: weather,
            importSource: importSource,
            bundledRouteID: bundledRouteID,
            isListPinned: isListPinned,
            listPinnedAt: listPinnedAt,
            isFavorite: isFavorite,
            favoritedAt: favoritedAt
        )
    }

    /// 즐겨찾기 섹션(즐겨찾기한 순).
    static func favoriteRecords(from records: [SavedHikingSession]) -> [SavedHikingSession] {
        records
            .filter(\.isFavorite)
            .sorted { $0.effectiveFavoritedAt < $1.effectiveFavoritedAt }
    }

    /// 즐겨찾기 제외, 상단 고정 순 → 최신순.
    static func mainListRecords(from records: [SavedHikingSession]) -> [SavedHikingSession] {
        records
            .filter { !$0.isFavorite }
            .sorted { lhs, rhs in
                if lhs.isListPinned != rhs.isListPinned { return lhs.isListPinned }
                if lhs.isListPinned, rhs.isListPinned {
                    return lhs.effectiveListPinnedAt < rhs.effectiveListPinnedAt
                }
                return lhs.endedAt > rhs.endedAt
            }
    }

    /// 상단 고정 정렬 기준 시각.
    var effectiveListPinnedAt: Date {
        listPinnedAt ?? endedAt
    }

    /// 즐겨찾기 정렬 기준 시각.
    var effectiveFavoritedAt: Date {
        favoritedAt ?? endedAt
    }

    nonisolated static func normalizedDisplayName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedMemo(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxMemoLength))
    }
}

extension SavedHikingSession {
    /// 고정된 순서대로 사진 메타데이터 반환.
    var mapPinnedPhotos: [HikingTrailPhoto] {
        mapPinnedPhotoIDs.compactMap { photoID in
            session.photos.first { $0.id == photoID }
        }
    }
}

#if os(iOS)
extension SavedHikingSession {
    var snapshotFileURL: URL? {
        guard UserDataPaths.isUserSelected, let root = UserDataPaths.activeUserRoot else { return nil }
        return HikingStorageLayout.resolvedSnapshotURL(
            recordID: id,
            storedFilename: snapshotFilename,
            in: root
        )
    }

    func trailPhotoURL(for photo: HikingTrailPhoto) -> URL {
        HikingTrailPhotoStore.fileURL(sessionID: id, filename: photo.filename)
    }
}
#endif

extension SavedHikingSession {
    var startedAt: Date? { session.effectiveStartedAt }

    /// 종료 시각 (목록 헤드라인용).
    var formattedDate: String {
        formattedEndedAt
    }

    var formattedStartedAt: String {
        guard let startedAt else { return "—" }
        return startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var formattedEndedAt: String {
        endedAt.formatted(date: .abbreviated, time: .shortened)
    }

    /// 목록·내비 제목. 사용자 지정 이름이 없으면 시작·종료 시각.
    var listTitle: String {
        displayName ?? formattedTimeRange
    }

    /// 공유·저장 카드 제목.
    var exportCardTitle: String {
        displayName ?? "[저장된 경로]"
    }

    var routeStartCoordinate: CLLocationCoordinate2D? {
        guard let point = session.points.first else { return nil }
        return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    /// 같은 날이면 시간만, 다른 날이면 날짜+시간.
    var formattedTimeRange: String {
        guard let startedAt else { return formattedEndedAt }
        let calendar = Calendar.current
        if calendar.isDate(startedAt, inSameDayAs: endedAt) {
            let start = startedAt.formatted(date: .omitted, time: .shortened)
            let end = endedAt.formatted(date: .omitted, time: .shortened)
            return "\(start) – \(end)"
        }
        return "\(formattedStartedAt) – \(formattedEndedAt)"
    }

    var formattedDuration: String {
        HikingDurationFormatting.displayString(
            elapsedSeconds: session.elapsedTime,
            style: .standard
        )
    }

    /// 좁은 통계 카드용 — 1시간 이상이면 `3h 25m` 형태로 한 줄에 맞춤.
    var formattedDurationCompact: String {
        HikingDurationFormatting.displayString(
            elapsedSeconds: session.elapsedTime,
            style: .compact
        )
    }

    var formattedDistance: String {
        "\(distanceValueText) \(distanceUnitText)"
    }

    var formattedElevationGain: String {
        "\(elevationValueText) \(elevationUnitText)"
    }

    var distanceValueText: String {
        String(format: "%.2f", session.totalDistance / 1_000)
    }

    var distanceUnitText: String { "km" }

    var elevationValueText: String {
        String(Int((session.elevationGainMeters ?? session.cumulativeElevationGain).rounded()))
    }

    var elevationUnitText: String { "m" }

    /// 평균 페이스(분/km). 거리·시간이 부족하면 nil.
    var averagePaceMinutesPerKilometer: Double? {
        let seconds = session.elapsedTime
        guard seconds > 0 else { return nil }
        let kilometers = session.totalDistance / 1_000
        guard kilometers >= 0.01 else { return nil }
        return (seconds / 60) / kilometers
    }

    var averageSpeedValueText: String {
        guard let pace = averagePaceMinutesPerKilometer else { return "0'00\"" }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d'%02d\"", minutes, seconds)
    }

    var averageSpeedUnitText: String { "/km" }

    /// 걸음수 데이터 존재 여부(0보 이상).
    var hasStepCount: Bool {
        (session.stepCount ?? 0) > 0
    }

    var stepCountValueText: String {
        let steps = session.stepCount ?? 0
        return NumberFormatter.stepCountFormatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }

    var stepCountUnitText: String { "걸음" }

    /// 활성 칼로리 존재 여부.
    var hasCalories: Bool {
        (session.activeEnergyKilocalories ?? 0) > 0
    }

    var caloriesValueText: String {
        let kilocalories = Int((session.activeEnergyKilocalories ?? 0).rounded())
        return NumberFormatter.stepCountFormatter.string(from: NSNumber(value: kilocalories)) ?? "\(kilocalories)"
    }

    var caloriesUnitText: String { "kcal" }
}

private extension NumberFormatter {
    static let stepCountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}
