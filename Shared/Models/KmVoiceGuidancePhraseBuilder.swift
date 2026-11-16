//
//  KmVoiceGuidancePhraseBuilder.swift
//  Shared
//
//  음성안내 문구 — 1km 구간 + 시작/종료 안내.
//  "N킬로미터 지점입니다. 이번 구간 {segment}, 총 산행 시간 {total}입니다."
//

import Foundation

enum KmVoiceGuidancePhraseBuilder {
    static let recordingStartPhrase = "기록을 시작합니다"

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

    /// 종료 안내 — 총 거리 + 소요 시간(분·초, 필요 시 시).
    static func recordingEndPhrase(
        distanceMeters: Double,
        totalSeconds: TimeInterval
    ) -> String {
        let distance = formatDistance(distanceMeters)
        let duration = formatDuration(totalSeconds)
        return "기록을 종료합니다. 총 거리 \(distance), 시간 \(duration)입니다."
    }

    /// 한국어 TTS용 시간 조각(문장 끝 「입니다」 없음 — 문구에서 한 번만 붙임).
    /// - 1분 미만 → "40초"
    /// - 1분 이상·1시간 미만 → "12분 34초"
    /// - 1시간 이상 → "1시간 5분 12초" (정시만 "1시간")
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(seconds.rounded()))
        if wholeSeconds < 60 {
            return "\(wholeSeconds)초"
        }

        let hours = wholeSeconds / 3_600
        let minutes = (wholeSeconds % 3_600) / 60
        let remainingSeconds = wholeSeconds % 60

        if hours == 0 {
            return "\(minutes)분 \(remainingSeconds)초"
        }
        if minutes == 0 && remainingSeconds == 0 {
            return "\(hours)시간"
        }
        return "\(hours)시간 \(minutes)분 \(remainingSeconds)초"
    }

    /// TTS용 거리 — 1km 미만은 미터, 이상은 소수점 킬로미터.
    static func formatDistance(_ meters: Double) -> String {
        let clamped = max(0, meters)
        if clamped < 1_000 {
            return "\(Int(clamped.rounded()))미터"
        }
        let kilometers = clamped / 1_000
        var text = String(format: "%.2f", kilometers)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return "\(text)킬로미터"
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

    /// 한 갱신에 여러 km를 넘길 때(Android `KmVoiceCrossing`과 동일) 구간을 균등 분배합니다.
    /// 두 번째부터 `0초`가 나오지 않고, 총 산행 시간은 km마다 누적됩니다.
    static func planCatchUpCrossings(
        pendingKilometers: [Int],
        baselineElapsed: TimeInterval,
        currentActiveElapsed: TimeInterval
    ) -> [(kilometers: Int, segmentSeconds: TimeInterval, totalSeconds: TimeInterval)] {
        guard !pendingKilometers.isEmpty else { return [] }
        let delta = max(0, currentActiveElapsed - max(0, baselineElapsed))
        let perSegment = delta / Double(pendingKilometers.count)
        return pendingKilometers.enumerated().map { index, kilometers in
            (
                kilometers: kilometers,
                segmentSeconds: perSegment,
                totalSeconds: max(0, baselineElapsed) + perSegment * Double(index + 1)
            )
        }
    }

    /// 안내 파일 없이 이미 넘긴 km를 시드할 때 — 거리를 비율로 나눠 경계 시각을 근사합니다.
    /// 전부 ‘지금’으로 찍으면 다음 구간이 결합 시각 기준이 됩니다.
    static func seedElapsedByDistance(
        crossedKilometers: Int,
        distanceMeters: Double,
        activeElapsed: TimeInterval
    ) -> [Int: TimeInterval] {
        guard crossedKilometers >= 1 else { return [:] }
        let clampedElapsed = max(0, activeElapsed)
        let distanceForFraction = max(distanceMeters, Double(crossedKilometers) * 1_000)
        var seeded: [Int: TimeInterval] = [:]
        for kilometers in 1...crossedKilometers {
            let fraction = min(1, (Double(kilometers) * 1_000) / distanceForFraction)
            seeded[kilometers] = clampedElapsed * fraction
        }
        return seeded
    }
}
