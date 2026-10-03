//
//  RouteMapBaseCaptureView.swift
//  sansan
//
//  기록 상세 SwiftUI Map(.standard)과 동일 — 지도 타일만 캡처(경로·마커는 합성 단계).
//

#if os(iOS)

import Combine
import MapKit
import SwiftUI

@MainActor
final class RouteMapBaseCaptureState: ObservableObject {
    @Published var cameraPosition: MapCameraPosition

    init(region: MKCoordinateRegion) {
        cameraPosition = .region(region)
    }

    func fitRoute(coordinates: [CLLocationCoordinate2D], mapSize: CGSize) {
        let region = HikingMapRegion.fitting(coordinates: coordinates, viewSize: mapSize)
        cameraPosition = .region(region)
    }
}

struct RouteMapBaseCaptureView: View {
    @ObservedObject var state: RouteMapBaseCaptureState
    let mapSize: CGSize
    var onCameraSettled: () -> Void

    var body: some View {
        Map(position: $state.cameraPosition, interactionModes: []) {}
            .mapStyle(.standard(elevation: .flat))
            .preferredColorScheme(.light)
            .onMapCameraChange(frequency: .onEnd) { _ in
                onCameraSettled()
            }
            .frame(width: mapSize.width, height: mapSize.height)
    }
}

#endif
