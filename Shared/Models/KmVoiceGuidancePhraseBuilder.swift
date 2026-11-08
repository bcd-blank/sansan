//
//  KmVoiceGuidancePhraseBuilder.swift
//  Shared
//
//  1km 음성 안내 문구 — 방금 끝난 1km 구간의 활동 시간(일시정지 제외) 기준.
//

import Foundation

enum KmVoiceGuidancePhraseBuilder {
    /// "N킬로 지점입니다. 걸린 시간은 …입니다."
    static func phrase(kilometers: Int, segmentSeconds: TimeInterval) -> String {
        let km = max(1, kilometers)
        return "\(km)킬로 지점입니다. 걸린 시간은 \(formatSegmentDuration(segmentSeconds))"
    }

    /// 구간 시간 한국어 TTS용 포맷.
    /// - 1분 미만 → "40초입니다"
    /// - 1분 이상·60분 미만 → 반올림 분 "15분입니다"
    /// - 정확히 N시간(반올림 분 기준) → "1시간입니다"
    /// - 60분 이상 → "1시간 5분입니다"
    static func formatSegmentDuration(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        if clamped < 60 {
            let wholeSeconds = Int(clamped.rounded())
            return "\(wholeSeconds)초입니다."
        }

        let totalMinutes = Int((clamped / 60.0).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(max(totalMinutes, 1))분입니다."
        }
        if minutes == 0 {
            return "\(hours)시간입니다."
        }
        return "\(hours)시간 \(minutes)분입니다."
    }

    /// 누적 거리에서 새로 넘긴 km 목록(이미 안내한 km 제외, 오름차순).
    static func newlyCrossedKilometers(
        distanceMeters: Double,
        alreadyAnnounced: Set<Int>
    ) -> [Int] {
        let crossed = Int(floor(max(0, distanceMeters) / 1_000))
        guard crossed >= 1 else { return [] }
        return (1...crossed).filter { !alreadyAnnounced.contains($0) }
    }

    /// N킬로 구간의 활동 시간 = 현재 활동 경과 − (N−1)킬로 통과 시점 활동 경과.
    static func segmentSeconds(
        for kilometers: Int,
        currentActiveElapsed: TimeInterval,
        elapsedAtAnnouncedKilometers: [Int: TimeInterval]
    ) -> TimeInterval {
        let previous = max(0, kilometers - 1)
        let baseline = previous == 0
            ? 0
            : (elapsedAtAnnouncedKilometers[previous] ?? 0)
        return max(0, currentActiveElapsed - baseline)
    }
}
