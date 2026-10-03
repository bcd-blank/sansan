//
//  HikingMapCaptureConfiguration.swift
//  Shared
//
//  상세 SwiftUI Map(.standard(elevation: .flat))과 동일한 MKMapView 설정.
//

#if canImport(MapKit)
import MapKit

enum HikingMapCaptureConfiguration {
    static var standard: MKMapConfiguration {
        MKStandardMapConfiguration(
            elevationStyle: .flat,
            emphasisStyle: .default
        )
    }
}
#endif
