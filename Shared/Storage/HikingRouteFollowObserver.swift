//
//  HikingRouteFollowObserver.swift
//  Shared
//

#if os(iOS)

import Combine
import CoreLocation
import Foundation

/// 저장된 경로를 기록 화면 지도에 오렌지색으로 표시할 때 사용합니다.
@MainActor
final class HikingRouteFollowObserver: ObservableObject {
    static let shared = HikingRouteFollowObserver()

    private static let recordBaseKey = "sansan.hikingRouteFollow.recordID"
    /// 구버전 번들 코스 follow 키 — 복원 시 무시하고 정리합니다.
    private static let legacyModeBaseKey = "sansan.hikingRouteFollow.mode"
    private static let legacyBundledBaseKey = "sansan.hikingRouteFollow.bundledRouteID"

    @Published private(set) var followedRecordID: UUID?

    private init() {
        restoreFromStorage()
    }

    func syncFromStorage() {
        restoreFromStorage()
    }

    var followedRecord: SavedHikingSession? {
        guard let followedRecordID else { return nil }
        return HikingRecordStore.shared.records.first(where: { $0.id == followedRecordID })
    }

    var followedRouteCoordinates: [CLLocationCoordinate2D] {
        guard let followedRecordID,
              let record = HikingRecordStore.shared.records.first(where: { $0.id == followedRecordID }) else {
            return []
        }
        return HikingSessionMetrics.resolvedDisplayRouteCoordinates(from: record.session)
    }

    var hasFollowedRoute: Bool {
        followedRouteCoordinates.count >= 2
    }

    var followedRouteTitle: String {
        followedRecord?.listTitle ?? "저장된 경로"
    }

    func setFollowedRoute(recordID: UUID) {
        guard isFollowableRecord(id: recordID) else { return }
        followedRecordID = recordID
        persist(recordID: recordID)
    }

    func clearFollowedRoute() {
        followedRecordID = nil
        persist(recordID: nil)
    }

    func clearIfFollowing(recordID: UUID) {
        guard followedRecordID == recordID else { return }
        clearFollowedRoute()
    }

    private func restoreFromStorage() {
        clearLegacyBundledFollowKeys()
        guard let stored = Self.loadStoredRecordID() else {
            followedRecordID = nil
            return
        }
        if !HikingRecordStore.shared.hasCompletedInitialLoad {
            followedRecordID = stored
            return
        }
        guard isFollowableRecord(id: stored) else {
            followedRecordID = nil
            return
        }
        followedRecordID = stored
    }

    private func isFollowableRecord(id: UUID) -> Bool {
        guard let record = HikingRecordStore.shared.records.first(where: { $0.id == id }) else {
            return false
        }
        return record.session.points.count >= 2
    }

    private func persist(recordID: UUID?) {
        let recordKey = Self.storageKey(for: Self.recordBaseKey)
        if let recordID {
            UserDefaults.standard.set(recordID.uuidString, forKey: recordKey)
        } else {
            UserDefaults.standard.removeObject(forKey: recordKey)
        }
    }

    private func clearLegacyBundledFollowKeys() {
        UserDefaults.standard.removeObject(forKey: Self.storageKey(for: Self.legacyModeBaseKey))
        UserDefaults.standard.removeObject(forKey: Self.storageKey(for: Self.legacyBundledBaseKey))
    }

    private static func storageKey(for base: String) -> String {
        guard let userID = UserDataPaths.currentUserID else { return base }
        return "\(base).\(userID)"
    }

    private static func loadStoredRecordID() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: storageKey(for: recordBaseKey)) else { return nil }
        return UUID(uuidString: raw)
    }
}

#endif
