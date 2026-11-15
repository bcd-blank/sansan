//
//  ShareSummaryOverlayTokens.swift
//  Shared
//
//  Cross-platform numbers for the share-summary text-area overlay.
//  Mirror of Shared/Resources/share_summary_overlay_tokens.json
//  (and Project store docs/share-overlay/measurements.json).
//

import Foundation

/// Design tokens for dominant-color share-summary scrims (color + multiply only).
enum ShareSummaryOverlayTokens {
    /// Peak scrim opacity before multiply blend.
    static let overlayOpacity: Double = 0.56

    /// Clamp band for extracted saturation (percent 0…100).
    static let saturationClampMinPercent: Double = 25
    static let saturationClampMaxPercent: Double = 45

    /// Default lightness (percent 0…100).
    static let lightnessPercent: Double = 26

    /// Lightness when white-on-overlay contrast is weak (percent 0…100).
    static let lightnessWeakContrastPercent: Double = 22

    /// If extracted S is below this percent, use `fallbackHex` instead of the hue.
    static let fallbackSaturationBelowPercent: Double = 20

    /// Fallback when the map is near-gray / desaturated.
    static let fallbackHex = "306458"

    /// Minimum contrast ratio (white text vs overlay fill) before dropping L to 22%.
    static let minimumContrastRatio: Double = 4.5
}
