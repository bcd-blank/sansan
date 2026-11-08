//
//  MapSummitMarkers.swift
//  sansan
//
//  경로 근처 산 정상 — 라이브 지도 주석. 저장·공유 PNG는 RouteSummitMarkerDrawing.
//

#if os(iOS)

import MapKit
import SwiftUI
import UIKit

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

/// 시작은 초록, 종료는 빨강, 일시정지는 오렌지. Android 경로 지도와 같습니다.
enum RoutePointColors {
    static let start = Color(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0)
    static let end = Color(red: 255.0 / 255.0, green: 59.0 / 255.0, blue: 48.0 / 255.0)
    static let pause = Color(red: 255.0 / 255.0, green: 149.0 / 255.0, blue: 0)
}

/// 정상 < 일시정지 < 거리·시간 라벨 < 시작·종료.
enum MapAnnotationZOrder {
    static let summit: Float = 100
    static let routePoint: Float = 400
    static let kilometer: Float = 900
    static let endpoint: Float = 1200
}

/// SwiftUI `Map` 주석의 `MKAnnotationView.zPriority`를 맞춥니다.
struct MapAnnotationZPriority: UIViewRepresentable {
    var priority: Float

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        apply(to: uiView, attempts: 8)
    }

    private func apply(to view: UIView, attempts: Int) {
        DispatchQueue.main.async {
            var ancestor: UIView? = view
            while let current = ancestor {
                if let annotationView = current as? MKAnnotationView {
                    let zPriority = MKAnnotationViewZPriority(rawValue: priority)
                    annotationView.zPriority = zPriority
                    annotationView.selectedZPriority = zPriority
                    return
                }
                ancestor = current.superview
            }
            if attempts > 0 {
                apply(to: view, attempts: attempts - 1)
            }
        }
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
                        .background { MapAnnotationZPriority(priority: MapAnnotationZOrder.summit) }
                }
            }
        }
    }
}

#endif
