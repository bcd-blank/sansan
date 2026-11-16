//
//  RouteKilometerMapMarkers.swift
//  sansan
//
//  Detail-map km markers — combined #007AFF capsule (spec-detail-labels-final).
//  Share-summary / card export keep white capsules via RouteKilometerMarkerDrawing.
//

#if os(iOS)

import SwiftUI
import UIKit

struct RouteKilometerRouteDot: View {
    private let diameter = RouteKilometerMarkerMetrics.routeDotDiameter
    private let border = RouteKilometerMarkerMetrics.routeDotBorderWidth

    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: diameter, height: diameter)
            .overlay {
                Circle()
                    .strokeBorder(Color(RouteKilometerMarkerMetrics.accentUIColor), lineWidth: border)
            }
    }
}

/// Combined blue capsule: both → `1km 16:50`; km-only / time-only → single part.
/// Fill #007AFF, white text (km 600 / time 400), white 1pt stroke, dual shadows.
struct RouteKilometerCombinedLabelCapsule: View {
    var distanceText: String?
    var timeText: String?

    private var parts: [(text: String, weight: Font.Weight, color: Color)] {
        let white = Color(RouteKilometerMarkerMetrics.detailLabelTextUIColor)
        if let distanceText, let timeText {
            return [
                (distanceText, .semibold, white),
                (timeText, .regular, white)
            ]
        }
        if let distanceText {
            return [(distanceText, .semibold, white)]
        }
        if let timeText {
            return [(timeText, .regular, white)]
        }
        return []
    }

    var body: some View {
        HStack(spacing: RouteKilometerMarkerMetrics.combinedInnerGap) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Text(part.text)
                    .font(.system(size: RouteKilometerMarkerMetrics.labelFontSize, weight: part.weight))
                    .foregroundStyle(part.color)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, RouteKilometerMarkerMetrics.labelPadH)
        .frame(height: RouteKilometerMarkerMetrics.labelHeight)
        .background(
            Color(RouteKilometerMarkerMetrics.detailLabelFillUIColor),
            in: Capsule(style: .continuous)
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    Color(RouteKilometerMarkerMetrics.detailLabelStrokeUIColor),
                    lineWidth: RouteKilometerMarkerMetrics.detailLabelStrokeWidth
                )
        }
        .shadow(
            color: Color(RouteKilometerMarkerMetrics.detailLabelShadowSecondary.color),
            radius: RouteKilometerMarkerMetrics.detailLabelShadowSecondary.radius,
            y: RouteKilometerMarkerMetrics.detailLabelShadowSecondary.y
        )
        .shadow(
            color: Color(RouteKilometerMarkerMetrics.detailLabelShadowPrimary.color),
            radius: RouteKilometerMarkerMetrics.detailLabelShadowPrimary.radius,
            y: RouteKilometerMarkerMetrics.detailLabelShadowPrimary.y
        )
    }
}

/// 경로 점 옆에 합친 거리·시간 라벨을 둡니다. 경로 좌표는 원 중심에 맞춥니다.
struct RouteKilometerHorizontalMarker: View {
    var distanceText: String?
    var timeText: String?
    let placesLabelOnLeadingSide: Bool
    var verticalOffset: CGFloat = 0
    /// When false, draw only the km dot (thinning hid this label).
    var showsLabel: Bool = true

    private let gap = RouteKilometerMarkerMetrics.labelGap

    var body: some View {
        ZStack {
            RouteKilometerRouteDot()
            if showsLabel,
               RouteKilometerMarkerMetrics.combinedLabel(distance: distanceText, time: timeText) != nil {
                RouteKilometerCombinedLabelCapsule(distanceText: distanceText, timeText: timeText)
                    .fixedSize()
                    .offset(x: horizontalOffset(capsuleWidth: capsuleWidth), y: verticalOffset)
            }
        }
    }

    private var capsuleWidth: CGFloat {
        RouteKilometerMarkerDrawing.capsuleSize(
            distanceLabel: distanceText,
            timeLabel: timeText,
            contentScale: 1
        ).width
    }

    private func horizontalOffset(capsuleWidth: CGFloat) -> CGFloat {
        // labelGap = center → near edge (S7).
        let distance = gap + capsuleWidth / 2
        return placesLabelOnLeadingSide ? -distance : distance
    }
}

#endif
