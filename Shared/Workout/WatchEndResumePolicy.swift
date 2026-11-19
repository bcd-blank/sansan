//
//  WatchEndResumePolicy.swift
//  Shared
//
//  Watch가 이미 저장·종료한 세션을 iPhone이 미러 백업/늦은 stop으로
//  "계속 기록"으로 되살리지 않도록 하는 순수 정책.
//

import Foundation

enum WatchEndResumePolicy {
    /// iPhone 미러(`!isLocationProducer`) 라이브 백업을 앱 시작 시 어떻게 처리할지.
    enum MirrorBackupAction: Equatable {
        /// 디스크 백업만으로 기록 UI를 켜지 않음 — WC가 살아 있으면 스냅샷으로 재부착.
        case deferForWatchSync
        /// 이미 종료·수신·저장된 세션 — 백업만 삭제.
        case clearOnly
    }

    /// 원격 Watch stop을 iPhone 기록 종료로 받아들일지(아니면 폰 인계 유지).
    static func shouldAcceptWatchStopAsEnd(
        liveState: HikingSessionState,
        isWatchDetachedForRecording: Bool,
        isPhoneRecordingFailoverActive: Bool,
        isWatchReachable: Bool,
        isWatchOwnedSession: Bool,
        stopCarriesFinishedSession: Bool
    ) -> Bool {
        guard liveState == .recording || liveState == .paused else { return false }
        // 이미 배터리 방전 등으로 폰이 인계한 뒤에는 늦은 Watch stop을 무시합니다.
        if isWatchDetachedForRecording || isPhoneRecordingFailoverActive {
            return false
        }
        // Watch 소유 미러 세션이거나, 완료 페이로드가 온 의도적 저장/종료는
        // Watch가 이미 unreachable이어도 종료로 받아들입니다.
        if isWatchOwnedSession || stopCarriesFinishedSession {
            return true
        }
        return isWatchReachable
    }

    static func mirrorBackupAction(
        sessionID: UUID,
        dismissedSessionID: UUID?,
        isAlreadySavedOrInboxed: Bool
    ) -> MirrorBackupAction {
        if dismissedSessionID == sessionID { return .clearOnly }
        if isAlreadySavedOrInboxed { return .clearOnly }
        return .deferForWatchSync
    }

    /// 지연된 미러 백업을 완료 기록으로 확정해도 되는지(아직 라이브 미러가 없을 때).
    static func shouldSettleDeferredMirrorBackup(
        liveState: HikingSessionState,
        isWatchReachable: Bool,
        isAlreadySavedOrInboxed: Bool,
        deferElapsed: TimeInterval,
        settleGrace: TimeInterval
    ) -> Bool {
        guard liveState == .idle else { return false }
        if isAlreadySavedOrInboxed { return true }
        if isWatchReachable { return false }
        return deferElapsed >= settleGrace
    }
}
