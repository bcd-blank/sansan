//
//  HikingConnectivityMessage.swift
//  Shared
//
//  WatchConnectivity 페이로드·키 정의.
//  Xcode: Shared/Connectivity 타겟 멤버십 → sansan, sansan Watch App
//

import Foundation

enum HikingConnectivityKeys {
    /// `updateApplicationContext` — 최신 라이브 스냅샷(JSON Data).
    static let sessionSnapshot = "sessionSnapshot"
    /// `sendMessage` / `transferUserInfo` — 명령 종류(Raw value).
    static let command = "command"
    /// `transferUserInfo` — 전체/증분 스냅샷(JSON Data).
    static let sessionTransfer = "sessionTransfer"
    /// `sendMessage` — 실시간 단일 GPS 포인트(JSON Data).
    static let latestPoint = "latestPoint"
    /// `sendMessage` — Watch 실시간 심박 샘플(JSON Data).
    static let heartRateSample = "heartRateSample"
}

/// 실시간 제어 메시지(iPhone ↔ Watch).
enum HikingSessionCommand: String, Codable, Sendable {
    case startRecording
    case pauseRecording
    case resumeRecording
    case stopRecording
    /// 요약 화면에서 저장하지 않고 폐기 — 상대 기기도 저장 없이 초기화.
    case discardRecording
    /// 상대 기기에 최신 스냅샷을 요청.
    case requestSync
    /// iPhone GPS 품질 저하 — 워치에 임시 GPS 보조 수집을 요청.
    case startLocationAssist
    /// GPS 품질 회복·일시정지·종료 — 워치 GPS 보조 수집을 중단.
    case stopLocationAssist
    /// 워치 연결이 끊겨 iPhone이 위치 기록을 이어받음 — 워치는 미러로 전환.
    case phoneTookOverRecording
}

/// WatchConnectivity로 주고받는 메시지 봉투.
enum HikingConnectivityMessage: Sendable {
    case command(HikingSessionCommand)
    case sessionSnapshot(HikingSessionData)
}

// MARK: - Codable helpers

extension HikingPoint {
    func encoded() throws -> Data {
        try JSONEncoder.hikingConnectivity.encode(self)
    }

    static func decoded(from data: Data) throws -> HikingPoint {
        try JSONDecoder.hikingConnectivity.decode(HikingPoint.self, from: data)
    }

    init?(message: [String: Any]) {
        guard
            let data = message[HikingConnectivityKeys.latestPoint] as? Data,
            let point = try? Self.decoded(from: data)
        else { return nil }
        self = point
    }

    var messagePayload: [String: Any] {
        guard let data = try? encoded() else { return [:] }
        return [HikingConnectivityKeys.latestPoint: data]
    }
}

extension HikingSessionData {
    func encoded() throws -> Data {
        try JSONEncoder.hikingConnectivity.encode(self)
    }

    static func decoded(from data: Data) throws -> HikingSessionData {
        try JSONDecoder.hikingConnectivity.decode(HikingSessionData.self, from: data)
    }
}

extension HikingSessionCommand {
    init?(dictionary: [String: Any]) {
        guard
            let raw = dictionary[HikingConnectivityKeys.command] as? String,
            let command = HikingSessionCommand(rawValue: raw)
        else { return nil }
        self = command
    }

    var dictionary: [String: Any] {
        [HikingConnectivityKeys.command: rawValue]
    }
}

extension HikingSessionData {
    init?(applicationContext: [String: Any]) {
        guard
            let data = applicationContext[HikingConnectivityKeys.sessionSnapshot] as? Data,
            let session = try? Self.decoded(from: data)
        else { return nil }
        self = session
    }

    var applicationContext: [String: Any] {
        guard let data = try? encoded() else { return [:] }
        return [HikingConnectivityKeys.sessionSnapshot: data]
    }

    init?(userInfo: [String: Any]) {
        guard
            let data = userInfo[HikingConnectivityKeys.sessionTransfer] as? Data,
            let session = try? Self.decoded(from: data)
        else { return nil }
        self = session
    }

    var userInfo: [String: Any] {
        guard let data = try? encoded() else { return [:] }
        return [HikingConnectivityKeys.sessionTransfer: data]
    }

    func userInfo(including command: HikingSessionCommand) -> [String: Any] {
        var payload = userInfo
        payload[HikingConnectivityKeys.command] = command.rawValue
        return payload
    }
}

extension JSONEncoder {
    static let hikingConnectivity: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let hikingConnectivity: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
