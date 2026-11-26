//
//  ThumbnailSwiftUIMapCaptureView.swift
//  sansan
//
//  목록 썸네일용 — 경로·녹지만 그리는 오프스크린 SwiftUI Map (사진 마커 없음).
//

#if os(iOS)

import MapKit
import SwiftUI

struct ThumbnailSwiftUIMapCaptureView: View {
    let coordinates: [CLLocationCoordinate2D]
    let viewSize: CGSize

    @State private var position: MapCameraPosition

    init(coordinates: [CLLocationCoordinate2D], viewSize: CGSize) {
        self.coordinates = coordinates
        self.viewSize = viewSize
        let region = HikingMapRegion.fitting(coordinates: coordinates, viewSize: viewSize)
        _position = State(initialValue: .region(region))
    }

    private var routeRailLayers: [(id: String, coordinates: [CLLocationCoordinate2D], isCasing: Bool)] {
        // Render zoom/size = thumbnail fit camera.
        let region = HikingMapRegion.fitting(coordinates: coordinates, viewSize: viewSize)
        let filleted = RouteCornerSmoothing.smoothCoordinates(
            coordinates,
            fittingRegion: region,
            mapWidth: viewSize.width,
            mapHeight: viewSize.height
        )
        let list = [filleted]
        var layers: [(id: String, coordinates: [CLLocationCoordinate2D], isCasing: Bool)] = []
        for (index, stretch) in list.enumerated() where stretch.count >= 2 {
            layers.append((id: "c\(index)", coordinates: stretch, isCasing: true))
            layers.append((id: "f\(index)", coordinates: stretch, isCasing: false))
        }
        return layers
    }

    var body: some View {
        Map(position: $position, interactionModes: []) {
            // Same stretch-split dual-rail as detail (JW crossing + no dashed caps).
            ForEach(routeRailLayers, id: \.id) { layer in
                MapPolyline(coordinates: layer.coordinates)
                    .stroke(
                        layer.isCasing
                            ? Color.white.opacity(0.9)
                            : Color(red: 0.12, green: 0.72, blue: 0.45),
                        style: StrokeStyle(
                            lineWidth: layer.isCasing ? 9 : 5,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(width: viewSize.width, height: viewSize.height)
    }
}

#endif
