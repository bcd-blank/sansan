//
//  RouteKilometerMarkerMetrics.swift
//  Shared
//
//  Shared km-label tokens for detail map, share-summary image, card export,
//  and flythrough. Combined white capsule when both distance + time are on.
//

import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

enum RouteKilometerMarkerMetrics {
    /// White fill + accent stroke km point.
    static let routeDotDiameter: CGFloat = 8
    static let routeDotBorderWidth: CGFloat = 2
    /// Gap between route point and label capsule (pt).
    static let labelGap: CGFloat = 10
    /// Inner gap between "1km" and "16:50" inside the combined capsule.
    static let combinedInnerGap: CGFloat = 5
    /// Combined capsule height / corner radius (pill).
    static let labelHeight: CGFloat = 24
    static let labelPadH: CGFloat = 9
    static let labelFontSize: CGFloat = 12
    /// Legacy scale hook — combined labels use absolute pt tokens above.
    static let markerLabelScale: CGFloat = 1

#if canImport(UIKit)
    static let accentUIColor = UIColor(red: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 1)
    static let inkUIColor = UIColor(red: 11 / 255, green: 13 / 255, blue: 31 / 255, alpha: 1)
    static let ink2UIColor = UIColor(red: 110 / 255, green: 110 / 255, blue: 115 / 255, alpha: 1)

    /// `1km 16:50` when both; otherwise the single available part.
    static func combinedLabel(distance: String?, time: String?) -> String? {
        switch (distance, time) {
        case let (d?, t?): return "\(d) \(t)"
        case let (d?, nil): return d
        case let (nil, t?): return t
        case (nil, nil): return nil
        }
    }
#endif
}
