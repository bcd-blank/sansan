//
//  RouteKilometerMapMarkers.swift
//  sansan
//

#if os(iOS)

import SwiftUI

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

    private let routeGreen = Color(red: 0.12, green: 0.72, blue: 0.45)

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(routeGreen, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

/// 경로 점 옆(좌·우)에 라벨을 둡니다. 경로 좌표는 원 중심에 맞춥니다.
struct RouteKilometerHorizontalMarker: View {
    let text: String
    let placesLabelOnLeadingSide: Bool

    private let gap = RouteKilometerMarkerMetrics.labelGap
    private let dotDiameter = RouteKilometerMarkerMetrics.routeDotDiameter

    var body: some View {
        ZStack {
            RouteKilometerRouteDot()
            RouteKilometerLabelCapsule(text: text)
                .fixedSize()
                .offset(x: labelOffsetX)
        }
    }

    private var labelOffsetX: CGFloat {
        let labelHalfWidth: CGFloat = 17
        let distance = dotDiameter / 2 + gap + labelHalfWidth
        return placesLabelOnLeadingSide ? -distance : distance
    }
}

#endif
