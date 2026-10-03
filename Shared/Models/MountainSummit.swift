//
//  MountainSummit.swift
//  Shared
//

import CoreLocation
import Foundation

nonisolated struct MountainSummit: Identifiable, Equatable, Hashable, Sendable {
    let id: Int64
    let name: String
    let latitude: Double
    let longitude: Double
    let elevationMeters: Double?

    nonisolated var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// OSM 원본 `name`의 통용 표시명 (구 지명·이칭 보정).
    nonisolated var displayName: String {
        MountainSummitNameCorrections.preferredName(for: self)
    }
}

extension MountainSummit: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case latitude
        case longitude
        case elevationMeters
    }
}
