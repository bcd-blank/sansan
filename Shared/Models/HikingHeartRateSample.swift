//
//  HikingHeartRateSample.swift
//  Shared
//

import Foundation

/// 기록 중 수집된 심박수 샘플.
nonisolated struct HikingHeartRateSample: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    /// 분당 심박 수(bpm).
    let bpm: Double
    let timestamp: Date

    nonisolated init(id: UUID = UUID(), bpm: Double, timestamp: Date) {
        self.id = id
        self.bpm = bpm
        self.timestamp = timestamp
    }
}

extension HikingHeartRateSample {
    func encoded() throws -> Data {
        try JSONEncoder.hikingConnectivity.encode(self)
    }

    static func decoded(from data: Data) throws -> HikingHeartRateSample {
        try JSONDecoder.hikingConnectivity.decode(HikingHeartRateSample.self, from: data)
    }

    init?(message: [String: Any]) {
        guard
            let data = message[HikingConnectivityKeys.heartRateSample] as? Data,
            let sample = try? Self.decoded(from: data)
        else { return nil }
        self = sample
    }

    var messagePayload: [String: Any] {
        guard let data = try? encoded() else { return [:] }
        return [HikingConnectivityKeys.heartRateSample: data]
    }
}
