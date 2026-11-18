//
//  RouteKilometerMarkerMetrics.swift
//  Shared
//
//  Shared km-label tokens for detail map, share-summary image, card export,
//  and flythrough. Share/card stay white capsules; record-detail map uses
//  blue #007AFF combined capsules (spec-detail-labels-final).
//

import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

enum RouteKilometerMarkerMetrics {
    /// Outer visual diameter of the km point (S6: Ø10 = white Ø6 + 2pt accent ring).
    static let routeDotDiameter: CGFloat = 10
    static let routeDotBorderWidth: CGFloat = 2
    /// Km-dot **center** → capsule near edge (S7).
    static let labelGap: CGFloat = 10
    /// Inner gap between "1km" and "16:50" inside the combined capsule.
    static let combinedInnerGap: CGFloat = 5
    /// Combined capsule height / corner radius (pill).
    static let labelHeight: CGFloat = 24
    static let labelPadH: CGFloat = 9
    static let labelFontSize: CGFloat = 12
    /// Legacy scale hook — combined labels use absolute pt tokens above.
    static let markerLabelScale: CGFloat = 1
    /// Detail-map wholesale hideSteps ladder (visible-only subset). 1 → 5 → 10 → 20 → 50.
    static let detailLabelHideSteps: [Int] = [1, 5, 10, 20, 50]
    /// Detail-map side inset for capsule bounds (x [24, W−24]).
    static let detailLabelSideInset: CGFloat = 24
    /// Detail-map vertical inset (y [8, H−8]).
    static let detailLabelVerticalInset: CGFloat = 8
    /// Collision pad between label boxes (0.5pt each → 1pt gap).
    static let detailLabelCollisionPad: CGFloat = 0.5

#if canImport(UIKit)
    static let accentUIColor = UIColor(red: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 1)
    static let inkUIColor = UIColor(red: 11 / 255, green: 13 / 255, blue: 31 / 255, alpha: 1)
    static let ink2UIColor = UIColor(red: 110 / 255, green: 110 / 255, blue: 115 / 255, alpha: 1)
    /// Record-detail map capsule fill (#007AFF).
    static let detailLabelFillUIColor = UIColor(red: 0 / 255, green: 122 / 255, blue: 255 / 255, alpha: 1)
    /// White text / stroke on detail blue capsules.
    static let detailLabelTextUIColor = UIColor.white
    static let detailLabelStrokeUIColor = UIColor.white
    static let detailLabelStrokeWidth: CGFloat = 1
    /// Shadow 0 1 2 #000 22%.
    static let detailLabelShadowPrimary = (
        color: UIColor.black.withAlphaComponent(0.22),
        radius: CGFloat(2),
        y: CGFloat(1)
    )
    /// Shadow 0 2 6 #0B0D1F 10%.
    static let detailLabelShadowSecondary = (
        color: UIColor(red: 11 / 255, green: 13 / 255, blue: 31 / 255, alpha: 0.10),
        radius: CGFloat(6),
        y: CGFloat(2)
    )

    /// `1km 16:50` when both; otherwise the single available part.
    static func combinedLabel(distance: String?, time: String?) -> String? {
        switch (distance, time) {
        case let (d?, t?): return "\(d) \(t)"
        case let (d?, nil): return d
        case let (nil, t?): return t
        case (nil, nil): return nil
        }
    }

    /// Time-only capsule uses medium (500) so gray text stays readable (S9).
    /// Detail blue capsules use regular (400) for time even when alone (spec §5).
    static func timeLabelWeight(hasDistance: Bool) -> UIFont.Weight {
        hasDistance ? .regular : .medium
    }

    static func detailTimeLabelWeight(hasDistance: Bool) -> UIFont.Weight {
        .regular
    }
#endif
}
