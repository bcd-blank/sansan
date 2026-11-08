//
//  KmVoiceGuidancePhraseBuilder.swift
//  Shared
//
//  1km 음성 안내 문구 — Android와 동일 템플릿.
//  "N킬로미터 지점입니다. 이번 구간 {segment}, 총 산행 시간 {total}입니다."
//

import Foundation

enum KmVoiceGuidancePhraseBuilder {
    /// - segmentSeconds: 방금 끝난 1km의 활동 시간(일시정지 제외)
    /// - totalSeconds: 화면 소요 시간(= `sessionData.elapsedTime`, 일시정지 제외 누적)
    static func phrase(
        kilometers: Int,
        segmentSeconds: TimeInterval,
        totalSeconds: TimeInterval
    ) -> String {
        let km = max(1, kilometers)
        let segment = formatDuration(segmentSeconds)
        let total = formatDuration(totalSeconds)
        return "\(km)킬로미터 지점입니다. 이번 구간 \(segment), 총 산행 시간 \(total)입니다."
    }

    /// 한국어 TTS용 시간 조각(문장 끝 「입니다」 없음 — 문구에서 한 번만 붙임).
    /// - 1분 미만 → "40초"
    /// - 1분 이상·60분 미만 → 반올림 분 "15분"
    /// - 정확히 N시간(반올림 분 기준) → "1시간"
    /// - 60분 이상 → "1시간 5분"
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        if clamped < 60 {
            let wholeSeconds = Int(clamped.rounded())
            return "\(wholeSeconds)초"
        }

        let totalMinutes = Int((clamped / 60.0).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours == 0 {
            return "\(max(totalMinutes, 1))분"
        }
        if minutes == 0 {
            return "\(hours)시간"
        }
        return "\(hours)시간 \(minutes)분"
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
