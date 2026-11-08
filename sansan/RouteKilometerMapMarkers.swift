//
//  RouteKilometerMapMarkers.swift
//  sansan
//

#if os(iOS)

import SwiftUI
import UIKit

struct RouteKilometerRouteDot: View {
    private let routeGreen = Color(red: 0.12, green: 0.72, blue: 0.45)
    private let diameter = RouteKilometerMarkerMetrics.routeDotDiameter
    private let border = RouteKilometerMarkerMetrics.routeDotBorderWidth

    var body: some View {
        Circle()
            .fill(routeGreen)
            .frame(width: diameter, height: diameter)
            .overlay {
                Circle()
                    .strokeBorder(.white, lineWidth: border)
            }
            .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
    }
}

struct RouteKilometerLabelCapsule: View {
    let text: String
    var fill: Color = Color(red: 0.12, green: 0.72, blue: 0.45)
    var labelScale: CGFloat = 1

    var body: some View {
        Text(text)
            .font(.system(size: 10 * labelScale, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6 * labelScale)
            .padding(.vertical, 3 * labelScale)
            .background(fill, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.9), lineWidth: labelScale)
            }
            .shadow(color: .black.opacity(0.2), radius: 2 * labelScale, y: labelScale)
    }
}

/// 경로 점 옆에 거리 라벨을 두고, 시간 라벨은 그 위에 간격을 두고 올립니다.
/// 경로 좌표는 원 중심에 맞춥니다.
struct RouteKilometerHorizontalMarker: View {
    var distanceText: String?
    var timeText: String?
    let placesLabelOnLeadingSide: Bool
    var verticalOffset: CGFloat = 0

    private let gap = RouteKilometerMarkerMetrics.labelGap
    private let stackGap: CGFloat = 3
    private let dotDiameter = RouteKilometerMarkerMetrics.routeDotDiameter
    private let routeGreen = Color(red: 0.12, green: 0.72, blue: 0.45)
    private let timeFill = Color(red: 0, green: 122.0 / 255.0, blue: 1)

    var body: some View {
        ZStack {
            RouteKilometerRouteDot()
            if let distanceText {
                let distanceSize = capsuleSize(
                    for: distanceText,
                    labelScale: RouteKilometerMarkerMetrics.markerLabelScale
                )
                RouteKilometerLabelCapsule(
                    text: distanceText,
                    fill: routeGreen,
                    labelScale: RouteKilometerMarkerMetrics.markerLabelScale
                )
                    .fixedSize()
                    .offset(x: horizontalOffset(capsuleWidth: distanceSize.width), y: verticalOffset)
                if let timeText {
                    let timeSize = capsuleSize(
                        for: timeText,
                        labelScale: RouteKilometerMarkerMetrics.markerLabelScale
                    )
                    RouteKilometerLabelCapsule(
                        text: timeText,
                        fill: timeFill,
                        labelScale: RouteKilometerMarkerMetrics.markerLabelScale
                    )
                        .fixedSize()
                        .offset(
                            x: horizontalOffset(capsuleWidth: distanceSize.width),
                            y: -(distanceSize.height / 2 + stackGap + timeSize.height / 2) + verticalOffset
                        )
                }
            } else if let timeText {
                RouteKilometerLabelCapsule(
                    text: timeText,
                    fill: timeFill,
                    labelScale: RouteKilometerMarkerMetrics.markerLabelScale
                )
                    .fixedSize()
                    .offset(
                        x: horizontalOffset(
                            capsuleWidth: capsuleSize(
                                for: timeText,
                                labelScale: RouteKilometerMarkerMetrics.markerLabelScale
                            ).width
                        ),
                        y: verticalOffset
                    )
            }
        }
    }

    private func horizontalOffset(capsuleWidth: CGFloat) -> CGFloat {
        let distance = dotDiameter / 2 + gap + capsuleWidth / 2
        return placesLabelOnLeadingSide ? -distance : distance
    }

    private func capsuleSize(for text: String, labelScale: CGFloat = 1) -> CGSize {
        let pointSize = 10 * labelScale
        let base = UIFont.systemFont(ofSize: pointSize, weight: .bold)
        let font = base.fontDescriptor.withDesign(.rounded).map {
            UIFont(descriptor: $0, size: pointSize)
        } ?? base
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(
            width: ceil(textSize.width) + 12 * labelScale,
            height: ceil(textSize.height) + 6 * labelScale
        )
    }
}

#endif
