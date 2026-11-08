//
//  KmVoiceGuidanceController.swift
//  Shared
//
//  iPhone 전용 1km 음성 안내.
//  Watch 기록도 iPhone이 미러 거리로 안내하며, Watch에서는 말하지 않아 중복을 막습니다.
//

#if os(iOS)

import AVFoundation
import Foundation
import os

@MainActor
final class KmVoiceGuidanceController: NSObject {
    static let shared = KmVoiceGuidanceController()

    nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.jw.sansan",
        category: "KmVoiceGuidance"
    )

    /// 시뮬레이터·디버그 검증용으로 최근 말한 문구를 남깁니다.
    private(set) var spokenPhrasesLog: [String] = []

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

    /// 거리·활동 경과가 갱신될 때 호출. 일시정지 중·토글 OFF면 안내하지 않습니다.
    func evaluate(
        sessionID evaluateSessionID: UUID,
        distanceMeters: Double,
        activeElapsed: TimeInterval,
        state: HikingSessionState
    ) {
        guard KmVoiceGuidancePreferences.isEnabled else { return }
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

        for kilometers in pending {
            let segment = KmVoiceGuidancePhraseBuilder.segmentSeconds(
                for: kilometers,
                currentActiveElapsed: activeElapsed,
                elapsedAtAnnouncedKilometers: elapsedAtAnnouncedKilometers
            )
            let phrase = KmVoiceGuidancePhraseBuilder.phrase(
                kilometers: kilometers,
                segmentSeconds: segment
            )
            announcedKilometers.insert(kilometers)
            elapsedAtAnnouncedKilometers[kilometers] = activeElapsed
            speak(phrase)
        }
        persist()
    }

    private func seedAlreadyCrossedKilometers(distanceMeters: Double, activeElapsed: TimeInterval) {
        let crossed = Int(floor(max(0, distanceMeters) / 1_000))
        guard crossed >= 1 else { return }
        for kilometers in 1...crossed {
            announcedKilometers.insert(kilometers)
            elapsedAtAnnouncedKilometers[kilometers] = max(0, activeElapsed)
        }
        Self.logger.notice(
            "seeded announced km 1...\(crossed) without speaking (late bind / restore)"
        )
    }

    private func speak(_ phrase: String) {
        spokenPhrasesLog.append(phrase)
        Self.logger.notice("speak: \(phrase, privacy: .public)")
        activateAudioSessionForSpeech()
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

#endif
