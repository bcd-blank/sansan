//
//  KmVoiceGuidanceOwnership.swift
//  Shared
//
//  1km 음성 안내 — 기기별 발화 소유권.
//  Watch 연결 시 Watch, 미연결 시 iPhone. km당 1회.
//

import Foundation

enum KmVoiceGuidanceOwnership {
    /// - recordingStartedOnWatch: 이번 세션을 Watch에서 시작했는지
    /// - isCounterpartReachable: WCSession 기준 상대 기기 reachable
    /// - watchYieldedToPhone: Watch가 폰 인계 후 미러로 내려갔는지(watchOS)
    static func shouldSpeakLocally(
        recordingStartedOnWatch: Bool,
        isCounterpartReachable: Bool,
        watchYieldedToPhone: Bool = false
    ) -> Bool {
#if os(watchOS)
        if watchYieldedToPhone { return false }
        if recordingStartedOnWatch { return true }
        // iPhone에서 시작: 연결 중에만 Watch가 말함(끊기면 iPhone이 이어받음)
        return isCounterpartReachable
#else
        // iPhone: Watch가 reachable이면 침묵(Watch가 말함). 끊기면 iPhone이 말함.
        return !isCounterpartReachable
#endif
    }
}
