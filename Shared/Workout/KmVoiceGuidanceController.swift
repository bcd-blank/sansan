//
//  KmVoiceGuidanceController.swift
//  Shared
//
//  1km 음성 안내 (iPhone · Watch).
//  발화 소유권은 KmVoiceGuidanceOwnership — Watch 연결 시 Watch, 미연결 시 iPhone.
//  announced 상태는 기기 간 동기화해 km당 1회만 말한다.
//

import AVFoundation
import Foundation
import os
#if os(watchOS)
import WatchKit
#endif

@MainActor
final class KmVoiceGuidanceController: NSObject {
    static let shared = KmVoiceGuidanceController()

    nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.jw.sansan",
        category: "KmVoiceGuidance"
    )

    /// 시뮬레이터·디버그 검증용으로 최근 말한 문구를 남깁니다.
    private(set) var spokenPhrasesLog: [String] = []

    /// 발화 직후 WorkoutManager가 상대 기기에 상태를 푸시할 때 사용.
    var onAnnouncedStateChanged: ((KmVoiceAnnouncedState) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var sessionID: UUID?
    private var announcedKilometers: Set<Int> = []
    private var elapsedAtAnnouncedKilometers: [Int: TimeInterval] = [:]
    private var didConfigureAudioSession = false

    private nonisolated static var persistenceURL: URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("km-voice-guidance-state.json")
    }

    private struct PersistedState: Codable, Sendable {
        var sessionID: UUID
        var announcedKilometers: [Int]
        var elapsedAtAnnouncedKilometers: [String: TimeInterval]
    }

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 새 기록 시작 시 호출 — 이전 세션 안내 상태를 지웁니다.
    func prepareForNewSession(_ newSessionID: UUID) {
        sessionID = newSessionID
        announcedKilometers = []
        elapsedAtAnnouncedKilometers = [:]
        spokenPhrasesLog = []
        persist()
    }

    /// 복원·미러 세션에 맞춰 상태를 로드하거나 맞춥니다.
    /// 디스크에 상태가 없고 이미 1km 이상이면 지난 km는 안내 완료로 시드해 재안내를 막습니다.
    func bindSession(
        _ bindSessionID: UUID,
        seedFromDistanceMeters: Double = 0,
        seedActiveElapsed: TimeInterval = 0
    ) {
        if sessionID == bindSessionID { return }
        if let persisted = loadPersisted(), persisted.sessionID == bindSessionID {
            sessionID = persisted.sessionID
            announcedKilometers = Set(persisted.announcedKilometers)
            elapsedAtAnnouncedKilometers = Dictionary(
                uniqueKeysWithValues: persisted.elapsedAtAnnouncedKilometers.compactMap { key, value in
                    guard let km = Int(key) else { return nil }
                    return (km, value)
                }
            )
            return
        }

        sessionID = bindSessionID
        announcedKilometers = []
        elapsedAtAnnouncedKilometers = [:]
        spokenPhrasesLog = []
        seedAlreadyCrossedKilometers(
            distanceMeters: seedFromDistanceMeters,
            activeElapsed: seedActiveElapsed
        )
        persist()
    }

    func clear() {
        sessionID = nil
        announcedKilometers = []
        elapsedAtAnnouncedKilometers = [:]
        spokenPhrasesLog = []
        clearPersisted()
        synthesizer.stopSpeaking(at: .immediate)
        deactivateAudioSessionIfNeeded()
    }

    /// 테스트용 — 디스크 상태는 유지한 채 인메모리만 비워 복원을 재현합니다.
    func resetInMemoryPreservingDiskForTests() {
        sessionID = nil
        announcedKilometers = []
        elapsedAtAnnouncedKilometers = [:]
        spokenPhrasesLog = []
        synthesizer.stopSpeaking(at: .immediate)
    }

    func currentAnnouncedState() -> KmVoiceAnnouncedState? {
        guard let sessionID else { return nil }
        return KmVoiceAnnouncedState(
            sessionID: sessionID,
            announcedKilometers: announcedKilometers.sorted(),
            elapsedAtAnnouncedKilometers: Dictionary(
                uniqueKeysWithValues: elapsedAtAnnouncedKilometers.map { (String($0.key), $0.value) }
            )
        )
    }

    /// 상대 기기가 이미 말한 km를 병합합니다(발화하지 않음).
    func mergeRemoteAnnouncedState(_ remote: KmVoiceAnnouncedState) {
        guard sessionID == nil || sessionID == remote.sessionID else { return }
        sessionID = remote.sessionID
        var changed = false
        for kilometers in remote.announcedKilometers where !announcedKilometers.contains(kilometers) {
            announcedKilometers.insert(kilometers)
            changed = true
        }
        for (key, value) in remote.elapsedAtAnnouncedKilometers {
            guard let kilometers = Int(key) else { continue }
            if let existing = elapsedAtAnnouncedKilometers[kilometers] {
                if value < existing {
                    elapsedAtAnnouncedKilometers[kilometers] = value
                    changed = true
                }
            } else {
                elapsedAtAnnouncedKilometers[kilometers] = value
                changed = true
            }
        }
        if changed {
            persist()
        }
    }

    /// 거리·활동 경과가 갱신될 때 호출. 일시정지 중이면 return.
    /// 토글 OFF여도 세션을 묶고 지난 km는 무발화 시드해, 다시 켤 때 소급 발화가 나지 않게 합니다.
    /// `shouldSpeak == false`(상대 기기가 소유)면 발화·시드 모두 하지 않아 소유 기기 동기화를 기다립니다.
    func evaluate(
        sessionID evaluateSessionID: UUID,
        distanceMeters: Double,
        activeElapsed: TimeInterval,
        state: HikingSessionState,
        shouldSpeak: Bool
    ) {
        guard state == .recording else { return }

        bindSession(
            evaluateSessionID,
            seedFromDistanceMeters: distanceMeters,
            seedActiveElapsed: activeElapsed
        )

        let pending = KmVoiceGuidancePhraseBuilder.newlyCrossedKilometers(
            distanceMeters: distanceMeters,
            alreadyAnnounced: announcedKilometers
        )
        guard !pending.isEmpty else { return }

        let preferenceOn = KmVoiceGuidancePreferences.isEnabled
        if !preferenceOn {
            applyPendingCrossings(
                pending,
                activeElapsed: activeElapsed,
                speakEnabled: false
            )
            persist()
            return
        }

        guard shouldSpeak else { return }

        applyPendingCrossings(
            pending,
            activeElapsed: activeElapsed,
            speakEnabled: true
        )
        persist()
        if let state = currentAnnouncedState() {
            onAnnouncedStateChanged?(state)
        }
    }

    /// 다중 km 도약 시 Android와 같이 구간을 균등 분배합니다. OFF면 발화 없이 시드만 합니다.
    private func applyPendingCrossings(
        _ pending: [Int],
        activeElapsed: TimeInterval,
        speakEnabled: Bool
    ) {
        let first = pending[0]
        let baseline: TimeInterval = first <= 1
            ? 0
            : (elapsedAtAnnouncedKilometers[first - 1] ?? 0)
        let plans = KmVoiceGuidancePhraseBuilder.planCatchUpCrossings(
            pendingKilometers: pending,
            baselineElapsed: baseline,
            currentActiveElapsed: activeElapsed
        )

        for plan in plans {
            announcedKilometers.insert(plan.kilometers)
            elapsedAtAnnouncedKilometers[plan.kilometers] = plan.totalSeconds
            guard speakEnabled else { continue }
            let phrase = KmVoiceGuidancePhraseBuilder.phrase(
                kilometers: plan.kilometers,
                segmentSeconds: plan.segmentSeconds,
                totalSeconds: plan.totalSeconds
            )
            speak(phrase)
        }

        // 마지막 km는 현재 활동 경과에 정확히 맞춰 다음 구간 기준을 고정합니다.
        if let last = pending.last {
            elapsedAtAnnouncedKilometers[last] = max(0, activeElapsed)
        }
    }

    private func seedAlreadyCrossedKilometers(distanceMeters: Double, activeElapsed: TimeInterval) {
        let crossed = Int(floor(max(0, distanceMeters) / 1_000))
        guard crossed >= 1 else { return }
        let seeded = KmVoiceGuidancePhraseBuilder.seedElapsedByDistance(
            crossedKilometers: crossed,
            distanceMeters: distanceMeters,
            activeElapsed: activeElapsed
        )
        for (kilometers, elapsed) in seeded {
            announcedKilometers.insert(kilometers)
            elapsedAtAnnouncedKilometers[kilometers] = elapsed
        }
        Self.logger.notice(
            "seeded announced km 1...\(crossed) without speaking (late bind / restore)"
        )
    }

    private func speak(_ phrase: String) {
        spokenPhrasesLog.append(phrase)
        Self.logger.notice("speak: \(phrase, privacy: .public)")
        activateAudioSessionForSpeech()
#if os(watchOS)
        WKInterfaceDevice.current().play(.notification)
#endif
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }

    /// `.playback` + duckOthers — 무음 스위치와 무관하게 안내(운동·내비 앱 관례).
    /// 다른 오디오는 잠시 줄였다가 발화 종료 후 세션을 내려 복구합니다.
    private func activateAudioSessionForSpeech() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try session.setActive(true, options: [])
            didConfigureAudioSession = true
        } catch {
            Self.logger.error("audio session activate failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deactivateAudioSessionIfNeeded() {
        guard didConfigureAudioSession else { return }
        didConfigureAudioSession = false
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: [.notifyOthersOnDeactivation]
            )
        } catch {
            Self.logger.error("audio session deactivate failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persist() {
        guard let sessionID else {
            clearPersisted()
            return
        }
        let state = PersistedState(
            sessionID: sessionID,
            announcedKilometers: announcedKilometers.sorted(),
            elapsedAtAnnouncedKilometers: Dictionary(
                uniqueKeysWithValues: elapsedAtAnnouncedKilometers.map { (String($0.key), $0.value) }
            )
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: Self.persistenceURL, options: .atomic)
    }

    private func loadPersisted() -> PersistedState? {
        guard let data = try? Data(contentsOf: Self.persistenceURL) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    private func clearPersisted() {
        try? FileManager.default.removeItem(at: Self.persistenceURL)
    }
}

/// WatchConnectivity로 동기화하는 안내 완료 상태.
struct KmVoiceAnnouncedState: Codable, Equatable, Sendable {
    var sessionID: UUID
    var announcedKilometers: [Int]
    var elapsedAtAnnouncedKilometers: [String: TimeInterval]
}

extension KmVoiceGuidanceController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard !self.synthesizer.isSpeaking else { return }
            self.deactivateAudioSessionIfNeeded()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard !self.synthesizer.isSpeaking else { return }
            self.deactivateAudioSessionIfNeeded()
        }
    }
}
