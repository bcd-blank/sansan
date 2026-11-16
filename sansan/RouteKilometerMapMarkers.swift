//
//  RouteKilometerMapMarkers.swift
//  sansan
//
//  Detail-map km markers — combined white capsule shared with summary export.
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

/// Combined white capsule: both → `1km 16:50`; km-only / time-only → single part.
struct RouteKilometerCombinedLabelCapsule: View {
    var distanceText: String?
    var timeText: String?

    private var parts: [(text: String, weight: Font.Weight, color: Color)] {
        if let distanceText, let timeText {
            return [
                (distanceText, .semibold, Color(RouteKilometerMarkerMetrics.inkUIColor)),
                (timeText, .regular, Color(RouteKilometerMarkerMetrics.ink2UIColor))
            ]
        }
        if let distanceText {
            return [(distanceText, .semibold, Color(RouteKilometerMarkerMetrics.inkUIColor))]
        }
        if let timeText {
            // S9: time-only uses medium + ink so gray-only stays readable.
            return [(timeText, .medium, Color(RouteKilometerMarkerMetrics.inkUIColor))]
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
        .background(Color.white, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color(RouteKilometerMarkerMetrics.inkUIColor).opacity(0.10), lineWidth: 0.5)
        }
        .shadow(color: Color(RouteKilometerMarkerMetrics.inkUIColor).opacity(0.10), radius: 3, y: 2)
    }
}

/// 경로 점 옆에 합친 거리·시간 라벨을 둡니다. 경로 좌표는 원 중심에 맞춥니다.
struct RouteKilometerHorizontalMarker: View {
    var distanceText: String?
    var timeText: String?
    let placesLabelOnLeadingSide: Bool
    var verticalOffset: CGFloat = 0

    private let gap = RouteKilometerMarkerMetrics.labelGap

    var body: some View {
        ZStack {
            RouteKilometerRouteDot()
            if RouteKilometerMarkerMetrics.combinedLabel(distance: distanceText, time: timeText) != nil {
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
