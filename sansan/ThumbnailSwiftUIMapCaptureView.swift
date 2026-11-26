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

    private var routeStretches: [[CLLocationCoordinate2D]] {
        let stretches = RouteSelfCrossing.chronologicalCoordinateStretches(in: coordinates)
        return stretches.isEmpty ? [coordinates] : stretches
    }

    var body: some View {
        Map(position: $position, interactionModes: []) {
            // Same stretch-split dual-rail as detail (JW crossing + no dashed caps).
            ForEach(Array(routeStretches.enumerated()), id: \.offset) { _, stretch in
                MapPolyline(coordinates: stretch)
                    .stroke(
                        Color.white.opacity(0.9),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
                    )
                MapPolyline(coordinates: stretch)
                    .stroke(
                        Color(red: 0.12, green: 0.72, blue: 0.45),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(width: viewSize.width, height: viewSize.height)
    }
}

#endif
