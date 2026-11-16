//
//  HikingTrailPhoto.swift
//  Shared
//
//  기록 중 촬영한 사진 — GPS 좌표에 연결.
//

import Foundation

/// 경로상 특정 위치에 연결된 트레일 사진 메타데이터.
nonisolated struct HikingTrailPhoto: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    /// `records/{sessionID}/photos/{photoID}.jpg`
    let filename: String

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        timestamp: Date = Date(),
        filename: String
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.filename = filename
    }
}

#if canImport(CoreLocation)
import CoreLocation

extension HikingTrailPhoto {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
#endif
