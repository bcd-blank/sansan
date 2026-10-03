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

    var body: some View {
        Map(position: $position, interactionModes: []) {
            MapPolyline(coordinates: coordinates)
                .stroke(
                    Color(red: 0.12, green: 0.72, blue: 0.45),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                )
        }
        .mapStyle(.standard(elevation: .flat))
        .frame(width: viewSize.width, height: viewSize.height)
    }
}

#endif
