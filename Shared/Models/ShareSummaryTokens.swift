//
//  ShareSummaryTokens.swift
//  Shared
//
//  share.summary.* design tokens for the A안 floating white card summary image.
//  Mirror of Shared/Resources/share_summary_tokens.json
//

import CoreGraphics
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

    static func hairlineWidth(scale: CGFloat) -> CGFloat {
        max(1 / max(scale, 1), 0.5 * scale)
    }

    // MARK: Colors (iOS accent #34C759)

    enum ColorHex {
        static let accent = "34C759"
        static let ink = "0B0D1F"
        static let ink2 = "6E6E73"
        static let ink3 = "8A8A8E"
        static let mapText = "636366"
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
    static let cardHeight: CGFloat = 320
    static let cardRadius: CGFloat = 24
    static let cardBlockGap: CGFloat = 16
    static let cardColumnWidth: CGFloat = 106
    static let cardColumnGap: CGFloat = 16

    // MARK: Type

    static let heroSize: CGFloat = 56
    static let heroUnitSize: CGFloat = 20
    static let metricSize: CGFloat = 28
    static let metricUnitSize: CGFloat = 13
    static let labelSize: CGFloat = 12
    static let metaSize: CGFloat = 13
    static let timeSize: CGFloat = 13
    static let legendSize: CGFloat = 12

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
    static let timelineDot: CGFloat = 9
    static let timelineLine: CGFloat = 36
    static let graphHeight: CGFloat = 56
    static let graphElevWidth: CGFloat = 2
    static let graphHRWidth: CGFloat = 1

    // MARK: Weather

    static let weatherMaxWidthFraction: CGFloat = 0.5
    static let weatherHeight: CGFloat = 48
    static let weatherPaddingH: CGFloat = 12
    static let weatherPaddingV: CGFloat = 8
    static let weatherRadius: CGFloat = 12
    static let weatherColumnWidth: CGFloat = 28
    static let weatherColumnGap: CGFloat = 8
    static let weatherIconSize: CGFloat = 18
    static let weatherIconTempGap: CGFloat = 2
    static let weatherTempSize: CGFloat = 12
    static let weatherMaxColumns = 6
    static let weatherMinScale: CGFloat = 0.85

    // MARK: Map insets

    static let mapSideInset: CGFloat = 24
    /// Bottom inset = cardHeight + cardInset + routeClearance (= cardHeight + 32).
    static var mapBottomInset: CGFloat { cardHeight + 32 }

    static func headerBottom(memoLineCount: Int) -> CGFloat {
        guard memoLineCount > 0 else { return headerBottomNoMemo }
        let lines = min(memoMaxLines, memoLineCount)
        return headerBottomNoMemo + memoGapFromTitle + CGFloat(lines) * memoLineHeight
    }

    static func mapTopInset(memoLineCount: Int) -> CGFloat {
        headerBottom(memoLineCount: memoLineCount) + routeClearance
    }

#if canImport(UIKit)
    static func memoLineCount(_ memo: String?, canvasWidth: CGFloat) -> Int {
        guard let raw = memo?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return 0
        }
        let scale = ptScale(for: canvasWidth)
        let width = (canvasWidth - headerInset * 2 * scale)
        let font = UIFont.systemFont(ofSize: memoFontSize * scale, weight: .medium)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineHeightMultiple = memoLineHeight / memoFontSize
        let bounds = (raw as NSString).boundingRect(
            with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraph,
                .kern: memoTracking * scale
            ],
            context: nil
        )
        let line = memoLineHeight * scale
        let counted = Int(ceil(bounds.height / max(line, 1)))
        return min(memoMaxLines, max(1, counted))
    }
#endif
}
