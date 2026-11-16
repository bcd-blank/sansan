//
//  HikingPoint.swift
//  Shared
//
//  iPhone · Apple Watch 공통 GPS 샘플 모델.
//  Xcode: Shared/Models 타겟 멤버십 → sansan, sansan Watch App
//

import CoreLocation
import Foundation

/// 등산 경로상의 단일 GPS 샘플.
nonisolated struct HikingPoint: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    /// 해수면 기준 고도(미터).
    let altitude: Double
    let timestamp: Date
    /// GPS 수평 정확도(노이즈 반경, 미터). 구버전 데이터는 nil.
    let horizontalAccuracy: Double?

    nonisolated init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        altitude: Double,
        timestamp: Date,
        horizontalAccuracy: Double? = nil
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
    }

    nonisolated var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
