//
//  MapKitHeadingPuckInject.swift
//  sansan
//
//  DEBUG / UITest only — Simulator has no magnetometer, so MapKit UserAnnotation
//  stays dot-only. `-UITestInjectHeading` draws a MapKit-standard blue-dot + soft
//  heading sector so we can capture & measure SoT for Android.
//

#if os(iOS) && DEBUG

import CoreLocation
import MapKit
import SwiftUI

enum UITestHeadingInject {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITestInjectHeading")
            || ProcessInfo.processInfo.environment["SANSAN_INJECT_HEADING"] == "1"
    }

    /// Fixed Seoul CBD point for beam SoT capture (matches simctl location set).
    static let captureCoordinate = CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780)
}

/// Soft circular-sector heading beam + white-ringed blue dot (MapKit-style).
/// Defaults mirror `ChromeSizes.MapUserLocation` (v28 beam-visible SoT).
struct MapKitHeadingPuckInjectView: View {
    var apertureDegrees: CGFloat = ChromeSizes.MapUserLocation.HeadingBeam.apertureAngleDegrees
    var lengthRadius: CGFloat = ChromeSizes.MapUserLocation.HeadingBeam.lengthRadius
    var fillRGB: (CGFloat, CGFloat, CGFloat) = (
        CGFloat(ChromeSizes.MapUserLocation.Dot.fillRGB.r) / 255,
        CGFloat(ChromeSizes.MapUserLocation.Dot.fillRGB.g) / 255,
        CGFloat(ChromeSizes.MapUserLocation.Dot.fillRGB.b) / 255
    )
    var opacityNear: CGFloat = ChromeSizes.MapUserLocation.HeadingBeam.opacityNear
    var fillDiameter: CGFloat = ChromeSizes.MapUserLocation.Dot.fillDiameter
    var strokeWidth: CGFloat = ChromeSizes.MapUserLocation.Dot.strokeWidth

    private var outerDiameter: CGFloat { fillDiameter + strokeWidth * 2 }

    var body: some View {
        let size = lengthRadius * 2
        ZStack {
            HeadingSectorShape(apertureDegrees: apertureDegrees)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: fillRGB.0, green: fillRGB.1, blue: fillRGB.2)
                                .opacity(opacityNear),
                            Color(red: fillRGB.0, green: fillRGB.1, blue: fillRGB.2)
                                .opacity(0)
                        ],
                        center: .center,
                        startRadius: outerDiameter * 0.35,
                        endRadius: lengthRadius
                    )
                )
                .frame(width: size, height: size)
                // Sector points up (heading-up / follow-with-heading pose).
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(Color.white)
                .frame(width: outerDiameter, height: outerDiameter)
            Circle()
                .fill(Color(red: fillRGB.0, green: fillRGB.1, blue: fillRGB.2))
                .frame(width: fillDiameter, height: fillDiameter)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

private struct HeadingSectorShape: Shape {
    var apertureDegrees: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let half = apertureDegrees / 2
        // 0° = +x; we rotate the view so visual up = heading.
        let start = Angle(degrees: -half)
        let end = Angle(degrees: half)
        var path = Path()
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: start,
            endAngle: end,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

#endif
