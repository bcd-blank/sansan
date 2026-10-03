//
//  MapSummitMarkers.swift
//  sansan
//
//  경로 근처 산 정상 — 라이브 지도 주석. 저장·공유 PNG는 RouteSummitMarkerDrawing.
//

#if os(iOS)

import MapKit
import SwiftUI

struct MapSummitMarkerView: View {
    let summit: MountainSummit

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.45, green: 0.34, blue: 0.24))
                .shadow(color: .white.opacity(0.85), radius: 1)

            Text(summit.displayName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summit.accessibilityLabel)
    }
}

private extension MountainSummit {
    var accessibilityLabel: String {
        if let elevationMeters {
            return "\(displayName) 정상, 고도 \(Int(elevationMeters.rounded()))미터"
        }
        return "\(displayName) 정상"
    }
}

struct RouteNearbySummitMapContent: MapContent {
    let summits: [MountainSummit]
    let showsSummits: Bool

    var body: some MapContent {
        if showsSummits, !summits.isEmpty {
            ForEach(summits) { summit in
                Annotation("", coordinate: summit.coordinate, anchor: .bottom) {
                    MapSummitMarkerView(summit: summit)
                }
            }
        }
    }
}

#endif
