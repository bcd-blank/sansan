//
//  TrailPhotoMapMarkerPlacement.swift
//  Shared
//

import Foundation

#if canImport(CoreLocation)
import CoreLocation

struct TrailPhotoMapMarkerPlacement: Identifiable, Sendable {
    let coordinate: CLLocationCoordinate2D
    let photos: [HikingTrailPhoto]

    var id: String {
        photos.map(\.id.uuidString).joined(separator: "-")
    }

    var isCluster: Bool { photos.count > 1 }
}

enum TrailPhotoMapMarkerPlacementBuilder {
    static func placements(for photos: [HikingTrailPhoto]) -> [TrailPhotoMapMarkerPlacement] {
        let sorted = photos.sorted { $0.timestamp < $1.timestamp }
        var groups: [[HikingTrailPhoto]] = []
        var consumed = Set<UUID>()

        for photo in sorted where !consumed.contains(photo.id) {
            let group = sorted.filter { candidate in
                !consumed.contains(candidate.id)
                    && HikingTrailPhotoCoordinateLayout.distanceMeters(
                        candidate.coordinate,
                        photo.coordinate
                    ) < TrailPhotoMarkerMetrics.sameLocationThresholdMeters
            }
            group.forEach { consumed.insert($0.id) }
            groups.append(group)
        }

        var result: [TrailPhotoMapMarkerPlacement] = []
        var placedCoordinates: [CLLocationCoordinate2D] = []

        for group in groups {
            guard let anchor = group.first?.coordinate else { continue }
            var displayCoordinate = anchor
            var attempt = 0

            while attempt < 16,
                  placedCoordinates.contains(where: {
                      HikingTrailPhotoCoordinateLayout.distanceMeters(displayCoordinate, $0)
                          < HikingTrailPhotoCoordinateLayout.minSeparationMeters
                  }) {
                displayCoordinate = HikingTrailPhotoCoordinateLayout.offsetCoordinate(
                    from: anchor,
                    meters: HikingTrailPhotoCoordinateLayout.minSeparationMeters,
                    bearingDegrees: Double(attempt) * 30
                )
                attempt += 1
            }

            placedCoordinates.append(displayCoordinate)
            result.append(
                TrailPhotoMapMarkerPlacement(
                    coordinate: displayCoordinate,
                    photos: group
                )
            )
        }

        return result
    }
}
#endif
