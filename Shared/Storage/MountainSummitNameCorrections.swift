//
//  MountainSummitNameCorrections.swift
//  Shared
//
//  OpenStreetMap natural=peak 이름은 구 지명·이칭이 남아 있는 경우가 많습니다.
//  앱 표시·공유용 통용명으로 보정합니다.
//

import CoreLocation
import Foundation

enum MountainSummitNameCorrections {
    /// OSM node id → 앱 표시명 (번들 JSON의 `name`은 OSM 원본 유지).
    nonisolated private static let idOverrides: [Int64: String] = [
        // 가평·양평 유명산(864m) — 옛 지명 마유산(馬遊山). 문헌·관광청은 유명산(有明山).
        5_388_363_536: "유명산",
    ]

    /// 좌표 범위 + OSM 원본명 → 표시명 (id가 바뀌어도 같은 산을 잡기 위함).
    nonisolated private static let regionalAliases: [RegionalAlias] = [
        RegionalAlias(
            rawName: "마유산",
            preferredName: "유명산",
            minLatitude: 37.52,
            maxLatitude: 37.64,
            minLongitude: 127.42,
            maxLongitude: 127.55
        ),
    ]

    nonisolated static func preferredName(for summit: MountainSummit) -> String {
        preferredName(
            id: summit.id,
            rawName: summit.name,
            coordinate: summit.coordinate
        )
    }

    nonisolated static func preferredName(
        id: Int64,
        rawName: String,
        coordinate: CLLocationCoordinate2D
    ) -> String {
        if let override = idOverrides[id] {
            return override
        }
        for alias in regionalAliases where alias.matches(rawName: rawName, coordinate: coordinate) {
            return alias.preferredName
        }
        return rawName
    }

    nonisolated static func applyingPreferredName(to summit: MountainSummit) -> MountainSummit {
        let preferred = preferredName(for: summit)
        guard preferred != summit.name else { return summit }
        return MountainSummit(
            id: summit.id,
            name: preferred,
            latitude: summit.latitude,
            longitude: summit.longitude,
            elevationMeters: summit.elevationMeters
        )
    }

    private struct RegionalAlias {
        let rawName: String
        let preferredName: String
        let minLatitude: Double
        let maxLatitude: Double
        let minLongitude: Double
        let maxLongitude: Double

        nonisolated func matches(rawName: String, coordinate: CLLocationCoordinate2D) -> Bool {
            guard rawName == self.rawName else { return false }
            return coordinate.latitude >= minLatitude
                && coordinate.latitude <= maxLatitude
                && coordinate.longitude >= minLongitude
                && coordinate.longitude <= maxLongitude
        }
    }
}
