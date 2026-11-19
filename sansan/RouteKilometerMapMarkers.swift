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
    var contentScale: CGFloat = 1
    private var diameter: CGFloat { RouteKilometerMarkerMetrics.routeDotDiameter * contentScale }
    private var border: CGFloat { RouteKilometerMarkerMetrics.routeDotBorderWidth * contentScale }

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
/// `contentScale` matches Simple SoT (`width/430`) so live detail pills match save size.
struct RouteKilometerCombinedLabelCapsule: View {
    var distanceText: String?
    var timeText: String?
    var contentScale: CGFloat = 1

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
        let s = contentScale
        HStack(spacing: RouteKilometerMarkerMetrics.combinedInnerGap * s) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Text(part.text)
                    .font(.system(size: RouteKilometerMarkerMetrics.labelFontSize * s, weight: part.weight))
                    .foregroundStyle(part.color)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, RouteKilometerMarkerMetrics.labelPadH * s)
        .frame(height: RouteKilometerMarkerMetrics.labelHeight * s)
        .background(
            Color(RouteKilometerMarkerMetrics.detailLabelFillUIColor),
            in: Capsule(style: .continuous)
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    Color(RouteKilometerMarkerMetrics.detailLabelStrokeUIColor),
                    lineWidth: RouteKilometerMarkerMetrics.detailLabelStrokeWidth * s
                )
        }
        .shadow(
            color: Color(RouteKilometerMarkerMetrics.detailLabelShadowSecondary.color),
            radius: RouteKilometerMarkerMetrics.detailLabelShadowSecondary.radius * s,
            y: RouteKilometerMarkerMetrics.detailLabelShadowSecondary.y * s
        )
        .shadow(
            color: Color(RouteKilometerMarkerMetrics.detailLabelShadowPrimary.color),
            radius: RouteKilometerMarkerMetrics.detailLabelShadowPrimary.radius * s,
            y: RouteKilometerMarkerMetrics.detailLabelShadowPrimary.y * s
        )
    }
}

/// 경로 점 옆에 합친 거리·시간 라벨을 둡니다. 경로 좌표는 원 중심에 맞춥니다.
struct RouteKilometerHorizontalMarker: View {
    var distanceText: String?
    var timeText: String?
    /// Capsule center relative to the km-dot center (final-spec v3).
    var centerOffset: CGPoint = .zero
    /// When false, draw only the km dot (thinning hid this label).
    var showsLabel: Bool = true
    /// Simple SoT scale (`width/430`); must match placement `contentScale`.
    var contentScale: CGFloat = 1

    /// Legacy convenience for call sites that still pass L/R + vertical.
    init(
        distanceText: String?,
        timeText: String?,
        placesLabelOnLeadingSide: Bool,
        verticalOffset: CGFloat = 0,
        showsLabel: Bool = true,
        contentScale: CGFloat = 1
    ) {
        let width = RouteKilometerMarkerDrawing.capsuleSize(
            distanceLabel: distanceText,
            timeLabel: timeText,
            contentScale: contentScale
        ).width
        let shift = RouteKilometerLabelShift(
            placesLabelOnLeadingSide: placesLabelOnLeadingSide,
            verticalOffset: verticalOffset,
            capsuleWidth: width > 0 ? width : 72 * contentScale,
            contentScale: contentScale
        )
        self.distanceText = distanceText
        self.timeText = timeText
        self.centerOffset = shift.centerOffset
        self.showsLabel = showsLabel
        self.contentScale = contentScale
    }

    init(
        distanceText: String?,
        timeText: String?,
        centerOffset: CGPoint,
        showsLabel: Bool = true,
        contentScale: CGFloat = 1
    ) {
        self.distanceText = distanceText
        self.timeText = timeText
        self.centerOffset = centerOffset
        self.showsLabel = showsLabel
        self.contentScale = contentScale
    }

    var body: some View {
        ZStack {
            RouteKilometerRouteDot(contentScale: contentScale)
            if showsLabel,
               RouteKilometerMarkerMetrics.combinedLabel(distance: distanceText, time: timeText) != nil {
                RouteKilometerCombinedLabelCapsule(
                    distanceText: distanceText,
                    timeText: timeText,
                    contentScale: contentScale
                )
                    .fixedSize()
                    .offset(x: centerOffset.x, y: centerOffset.y)
            }
        }
    }
}

#endif
