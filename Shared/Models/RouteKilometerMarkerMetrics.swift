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
    /// Combined capsule height / corner radius (pill). Shared Simple + detail.
    static let labelHeight: CGFloat = 24
    static let labelPadH: CGFloat = 9
    static let labelFontSize: CGFloat = 12
    /// Capsule outline width — Simple white and detail blue share this (color differs).
    static let labelStrokeWidth: CGFloat = 0.5
    /// Corner radius of the combined pill (= height/2).
    static var labelCornerRadius: CGFloat { labelHeight / 2 }
    /// Design canvas width shared with Simple Grey/Color (`ShareSummaryTokens.canvasWidth`).
    /// Detail + Data Card label `contentScale` must use this denominator so visible
    /// pill size matches Simple (not the old detail layout width 377).
    static let labelDesignCanvasWidth: CGFloat = 430
    /// Horizontal inset of the detail / Data Card map vs Simple full-bleed
    /// (`HikingRecordCardLayout.detailContentWidthInset`). Label scale uses
    /// full-bleed width so same-canvas saves match Simple ±1px.
    static let labelFullBleedWidthInset: CGFloat = 16
    /// Legacy scale hook — combined labels use absolute pt tokens above.
    static let markerLabelScale: CGFloat = 1

    /// Label content scale for a canvas/map width (Simple SoT = width / 430).
    /// - Parameter fullBleed: Detail / Data Card maps are inset by
    ///   `labelFullBleedWidthInset`; pass `true` so scale matches Simple’s
    ///   full-bleed canvas (screen-pt parity + same-canvas ±1px).
    static func labelContentScale(forWidth width: CGFloat, fullBleed: Bool = false) -> CGFloat {
        let sotWidth = fullBleed ? width + labelFullBleedWidthInset : width
        guard sotWidth > 0 else { return 1 }
        return sotWidth / labelDesignCanvasWidth
    }

    /// Live detail on-screen scale — fill AABB **65px @3x** (= Simple summary SoT ±1).
    /// Frame pt targets 68px @3x because strict blue-fill AABB under-reads ~3px vs
    /// the SwiftUI layout height (anti-alias / stroke).
    static var liveDetailLabelContentScale: CGFloat {
        (68.0 / 3.0) / labelHeight
    }
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
    /// Alias — same geometric stroke as Simple (`labelStrokeWidth`).
    static var detailLabelStrokeWidth: CGFloat { labelStrokeWidth }

    /// `1km 16:50` when both; otherwise the single available part.
    static func combinedLabel(distance: String?, time: String?) -> String? {
        switch (distance, time) {
        case let (d?, t?): return "\(d) \(t)"
        case let (d?, nil): return d
        case let (nil, t?): return t
        case (nil, nil): return nil
        }
    }

    /// Km always semibold; time regular when paired, medium when time-only (S9).
    /// Detail blue uses the **same** weights — only fill/text color differs.
    static func timeLabelWeight(hasDistance: Bool) -> UIFont.Weight {
        hasDistance ? .regular : .medium
    }

    static func detailTimeLabelWeight(hasDistance: Bool) -> UIFont.Weight {
        timeLabelWeight(hasDistance: hasDistance)
    }

    /// Km label weight — shared Simple + detail.
    static let distanceLabelWeight: UIFont.Weight = .semibold
#endif
}
