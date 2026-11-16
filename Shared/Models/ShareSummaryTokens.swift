//
//  ShareSummaryTokens.swift
//  Shared
//
//  share.summary.* design tokens for the A안 floating white card summary image.
//  Mirror of Shared/Resources/share_summary_tokens.json
//

import CoreGraphics
import CoreText
import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Cross-platform numbers for the share-summary (9:16) image. Values are in design pt
/// at `canvasWidth` = 430; multiply by `ptScale(for:)` for a given output canvas.
enum ShareSummaryTokens {
    static let canvasWidth: CGFloat = 430
    static let canvasAspect: CGFloat = 16.0 / 9.0

    static func ptScale(for canvasWidth: CGFloat) -> CGFloat {
        guard canvasWidth > 0 else { return 1 }
        return canvasWidth / Self.canvasWidth
    }

    /// Pixel height = ceil(widthPx × 16/9); returns size in points for the given point width + scale.
    static func canvasSize(widthPoints: CGFloat, pixelScale: CGFloat) -> CGSize {
        let widthPx = widthPoints * pixelScale
        let heightPx = ceil(widthPx * canvasAspect)
        return CGSize(width: widthPoints, height: heightPx / max(pixelScale, 1))
    }

    static func hairlineWidth(scale: CGFloat) -> CGFloat {
        0.5 * scale
    }

    // MARK: Colors (iOS accent #34C759)

    enum ColorHex {
        static let accent = "34C759"
        static let ink = "0B0D1F"
        static let ink2 = "6E6E73"
        static let ink3 = "8A8A8E"
        static let mapText = "636366"
        static let mapLabel = "9A9A9E"
        static let hairline = "E5E5EA"
        static let track = "D1D1D6"
        static let hr = "AEAEB2"
        static let surface = "FFFFFF"
        static let mapPaper = "F0F0F0"
        static let mapRoad = "FDFDFD"
    }

#if canImport(UIKit)
    static let accentUIColor = UIColor(red: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 1)
    static let inkUIColor = UIColor(red: 11 / 255, green: 13 / 255, blue: 31 / 255, alpha: 1)
    static let ink2UIColor = UIColor(red: 110 / 255, green: 110 / 255, blue: 115 / 255, alpha: 1)
    static let mapTextUIColor = UIColor(red: 99 / 255, green: 99 / 255, blue: 102 / 255, alpha: 1)
    static let hairlineUIColor = UIColor(red: 229 / 255, green: 229 / 255, blue: 234 / 255, alpha: 1)
    static let trackUIColor = UIColor(red: 209 / 255, green: 209 / 255, blue: 214 / 255, alpha: 1)
    static let hrUIColor = UIColor(red: 174 / 255, green: 174 / 255, blue: 178 / 255, alpha: 1)
    static let surfaceUIColor = UIColor.white
    static let mapPaperUIColor = UIColor(red: 240 / 255, green: 240 / 255, blue: 240 / 255, alpha: 1)
    static let mapRoadUIColor = UIColor(red: 253 / 255, green: 253 / 255, blue: 253 / 255, alpha: 1)
#endif

    // MARK: Header

    static let headerTop: CGFloat = 24
    static let headerInset: CGFloat = 40
    static let headerRow1Height: CGFloat = 48
    static let headerLogoHeight: CGFloat = 32
    static let headerTitleGap: CGFloat = 8
    static let headerTitleSize: CGFloat = 20
    static let headerTitleLineHeight: CGFloat = 24
    /// Memo-absent header bottom (top + row1 + titleGap + title).
    static let headerBottomNoMemo: CGFloat = 104

    // MARK: Memo

    static let memoFontSize: CGFloat = 12
    static let memoLineHeight: CGFloat = 17
    static let memoTracking: CGFloat = -0.1
    static let memoGapFromTitle: CGFloat = 8
    static let memoMaxLines = 3
    static let routeClearance: CGFloat = 16
    static let fadeTail: CGFloat = 96
    static let fadeSolidOpacity: CGFloat = 0.97

    // MARK: Card

    static let cardInset: CGFloat = 16
    static let cardPaddingH: CGFloat = 24
    static let cardPaddingTop: CGFloat = 20
    static let cardPaddingBottom: CGFloat = 20
    /// Designer-measured content sum (spec S3); replaces prior 320.
    static let cardHeight: CGFloat = 324.5
    static let cardRadius: CGFloat = 24
    static let cardBlockGap: CGFloat = 16
    static let cardColumnWidth: CGFloat = 106
    static let cardColumnGap: CGFloat = 16

    // MARK: Type

    static let heroSize: CGFloat = 56
    static let heroLineHeight: CGFloat = 56
    static let heroUnitSize: CGFloat = 20
    static let heroUnitGap: CGFloat = 6
    static let metricSize: CGFloat = 28
    static let metricLineHeight: CGFloat = 28
    static let metricUnitSize: CGFloat = 13
    /// Number → unit (e.g. `1`→`h`).
    static let metricUnitGap: CGFloat = 2
    /// Unit → next number (e.g. `h`→`47`).
    static let metricUnitTrailing: CGFloat = 6
    /// Scale down long metric values; never truncate with `…` (S1).
    static let metricMinScale: CGFloat = 0.82
    static let labelSize: CGFloat = 12
    static let labelLineHeight: CGFloat = 16
    static let metaSize: CGFloat = 13
    static let metaLineHeight: CGFloat = 16
    static let metaUnitGap: CGFloat = 4
    static let timeSize: CGFloat = 13
    static let timeLineHeight: CGFloat = 16
    static let legendSize: CGFloat = 12
    static let legendLineHeight: CGFloat = 16

    // MARK: Timeline (S4)

    /// Dot center x on the 430pt canvas (= 3rd column axis).
    static let timelineDotX: CGFloat = 284
    /// First time-row top relative to card top.
    static let timelineFirstRowTop: CGFloat = 22
    static let timelineDot: CGFloat = 9
    static let timelineLine: CGFloat = 36
    /// Vertical gap between time row and connector line.
    static let timelineRowGap: CGFloat = 2
    /// Dot-center spacing = row 16 + 2 + line 36 + 2.
    static var timelineDotSpacing: CGFloat { timeLineHeight + timelineRowGap + timelineLine + timelineRowGap }
    static let timelineTimeGap: CGFloat = 8

    // MARK: Route / markers (pt)

    static let routeWidth: CGFloat = 4.5
    static let routeCasing: CGFloat = 8
    static let markerOuter: CGFloat = 18
    static let markerInner: CGFloat = 12
    /// Km-label tokens live in `RouteKilometerMarkerMetrics` (shared with detail map).
    static var kmDot: CGFloat { RouteKilometerMarkerMetrics.routeDotDiameter }
    static var kmDotStroke: CGFloat { RouteKilometerMarkerMetrics.routeDotBorderWidth }
    static var kmLabelHeight: CGFloat { RouteKilometerMarkerMetrics.labelHeight }
    static var kmLabelPadH: CGFloat { RouteKilometerMarkerMetrics.labelPadH }
    static var kmLabelGap: CGFloat { RouteKilometerMarkerMetrics.combinedInnerGap }
    static var kmLabelOffset: CGFloat { RouteKilometerMarkerMetrics.labelGap }
    static var kmLabelFont: CGFloat { RouteKilometerMarkerMetrics.labelFontSize }
    static let graphHeight: CGFloat = 56
    static let graphElevWidth: CGFloat = 2
    static let graphHRWidth: CGFloat = 1
    static let graphLegendSwatchWidth: CGFloat = 12
    static let graphLegendElevHeight: CGFloat = 2
    static let graphLegendHRHeight: CGFloat = 1
    static let graphLegendGap: CGFloat = 6
    static let graphLegendBlockGap: CGFloat = 16
    static let graphGapAbove: CGFloat = 8

    // MARK: Attribution (§13)

    /// 「지도」 / TileJSON text size.
    static let attributionFontSize: CGFloat = 10
    static let attributionLineHeight: CGFloat = 12
    static let attributionWeight: CGFloat = 500
    /// Apple logo glyph height (iOS).
    static let attributionLogoHeight: CGFloat = 9
    static let attributionLogoGap: CGFloat = 2
    static let attributionGapAboveCard: CGFloat = 8
    static let attributionX: CGFloat = 40
    static let attributionMaxWidth: CGFloat = 350
    /// Paper halo behind credit so basemap roads under the mark stay ≥4.5:1 (impl3 #15).
    static let attributionHaloBlur: CGFloat = 2
    /// Legacy alias — line box height.
    static var attributionHeight: CGFloat { attributionLineHeight }

    // MARK: Weather

    static let weatherMaxWidthFraction: CGFloat = 0.5
    static let weatherHeight: CGFloat = 48
    static let weatherPaddingH: CGFloat = 12
    static let weatherPaddingV: CGFloat = 8
    static let weatherRadius: CGFloat = 12
    static let weatherColumnWidth: CGFloat = 28
    static let weatherColumnGap: CGFloat = 8
    /// SF Symbol `font(.system(size:))` point size (S12).
    static let weatherIconSize: CGFloat = 18
    static let weatherIconTempGap: CGFloat = 2
    static let weatherTempSize: CGFloat = 12
    static let weatherMaxColumns = 6
    static let weatherMinScale: CGFloat = 0.85

    // MARK: Map insets

    static let mapSideInset: CGFloat = 24
    /// Bottom inset = cardHeight + cardInset + routeClearance + marker radius
    /// so the white endpoint circle stays above the card (S3 + finding 7).
    static var mapBottomInset: CGFloat { cardHeight + 32 + markerOuter / 2 }

    static func headerBottom(memoLineCount: Int) -> CGFloat {
        guard memoLineCount > 0 else { return headerBottomNoMemo }
        let lines = min(memoMaxLines, memoLineCount)
        return headerBottomNoMemo + memoGapFromTitle + CGFloat(lines) * memoLineHeight
    }

    /// Top inset keeps marker outer edge below headerBottom + routeClearance.
    static func mapTopInset(memoLineCount: Int) -> CGFloat {
        headerBottom(memoLineCount: memoLineCount) + routeClearance + markerOuter / 2
    }

    /// Y where the solid paper fade ends (headerBottom + routeClearance), before the 96pt falloff.
    static func fadeSolidEnd(memoLineCount: Int) -> CGFloat {
        headerBottom(memoLineCount: memoLineCount) + routeClearance
    }

#if canImport(UIKit)
    static func memoLineCount(_ memo: String?, canvasWidth: CGFloat) -> Int {
        guard let raw = memo?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return 0
        }
        let scale = ptScale(for: canvasWidth)
        let width = max(canvasWidth - headerInset * 2 * scale, 1)
        let font = UIFont.systemFont(ofSize: memoFontSize * scale, weight: .medium)
        let line = memoLineHeight * scale
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = line
        paragraph.maximumLineHeight = line
        paragraph.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            .kern: memoTracking * scale
        ]
        let ns = NSAttributedString(string: raw, attributes: attrs)
        // Count wrapped lines via typesetter (framesetter/boundingRect under-count Hangul).
        let typesetter = CTTypesetterCreateWithAttributedString(ns as CFAttributedString)
        var offset = 0
        var counted = 0
        while offset < ns.length && counted < memoMaxLines {
            let breakCount = CTTypesetterSuggestLineBreak(typesetter, offset, Double(width))
            if breakCount <= 0 { break }
            offset += breakCount
            counted += 1
        }
        if offset < ns.length { counted = memoMaxLines }
        return min(memoMaxLines, max(1, counted))
    }
#endif
}
