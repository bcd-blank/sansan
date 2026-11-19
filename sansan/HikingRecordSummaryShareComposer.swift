//
//  HikingRecordSummaryShareComposer.swift
//  sansan
//
//  Share-summary: Simple Grey (gray map + white card) and Simple Color
//  (color map + liquid-glass card). Layout from share.summary.* tokens.
//

#if os(iOS)

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import SwiftUI
import UIKit

@MainActor
enum HikingRecordSummaryShareComposer {
    enum Variant: Sendable {
        case simpleGrey
        case simpleColor

        var appearance: HikingRouteSnapshotAppearance {
            switch self {
            case .simpleGrey: .shareSummary
            case .simpleColor: .shareSummaryColor
            }
        }

        static func fromPreferences() -> Variant {
            HikingRecordImageSavePreferences.style == .simpleColor ? .simpleColor : .simpleGrey
        }
    }

    static func render(
        record: SavedHikingSession,
        mapOptions: HikingShareMapExportOptions,
        variant: Variant = .fromPreferences()
    ) async -> UIImage? {
        let width = HikingRecordShareDeviceMetrics.fullScreenBounds.width
        let scale = HikingRecordShareDeviceMetrics.nativeScale
        let canvas = ShareSummaryTokens.canvasSize(widthPoints: width, pixelScale: scale)
        let s = ShareSummaryTokens.ptScale(for: canvas.width)
        let memoLines = ShareSummaryTokens.memoLineCount(record.memo, canvasWidth: canvas.width)
        var captureOptions = HikingShareExportPreferences.applyingSharePhotoFeatureFlags(mapOptions)
        captureOptions.showsPinnedThumbnails = false
        guard let map = await HikingRouteSnapshotGenerator.fittedMapImage(
            record: record,
            canvasSize: canvas,
            pixelScale: scale,
            mapOptions: captureOptions,
            insetTop: ShareSummaryTokens.mapTopInset(memoLineCount: memoLines) * s,
            insetBottom: ShareSummaryTokens.mapBottomInset * s,
            insetLeft: ShareSummaryTokens.mapRouteSideInset * s,
            insetRight: ShareSummaryTokens.mapRouteSideInset * s,
            routeFillFraction: 1,
            appearance: variant.appearance,
            fadeSolidEndY: ShareSummaryTokens.fadeSolidEnd(memoLineCount: memoLines) * s
        ) else { return nil }

        let page = SummaryMapSharePage(
            record: record,
            mapImage: map,
            memoLineCount: memoLines,
            showsWeatherLabel: mapOptions.showsWeatherLabel,
            variant: variant
        )
        .frame(width: canvas.width, height: canvas.height)
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: page)
        renderer.proposedSize = ProposedViewSize(width: canvas.width, height: canvas.height)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

// MARK: - Elev legend swatch (baked #FF8D28 — ImageRenderer/glass must not grey it)

private enum ShareSummaryElevLegendSwatch {
    static func image(width: CGFloat, height: CGFloat) -> UIImage {
        let size = CGSize(width: max(width, 1), height: max(height, 1))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ShareSummaryTokens.chartElevUIColor.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Liquid glass backdrop (baked into PNG — ImageRenderer cannot flatten materials)

private enum ShareSummaryGlassBackdrop {
    /// Android `ShareSummaryGlass` code + v7 measured plate tune.
    /// Bake in **pixel space** with `designScale = widthPx/430` + stack-blur.
    /// Fill/wash lowered from 0.38/0.12 — mid-card plate was milky vs Android; 0.26/0.08 for map bleed.
    static let blurRadiusPt: CGFloat = 36
    static let glassFillAlpha: CGFloat = 0.26
    static let washAlpha: CGFloat = 0.08
    static let rimAlpha: CGFloat = 0.72
    static let catchLightAlpha: CGFloat = 0.55
    private static let blurDownscaleFactor = 4

    /// Map blur + translucent fill + edge highlight, clipped to the card.
    /// Pixel recipe mirrors Android `ShareSummaryGlass.bake` (not point×nativeScale).
    static func bake(
        mapImage: UIImage,
        cardRect: CGRect,
        cornerRadius: CGFloat
    ) -> UIImage? {
        guard let cgImage = mapImage.cgImage else { return nil }
        let imageScale = max(mapImage.scale, 1)
        let widthPx = mapImage.size.width * imageScale
        // Android: `scale = ShareSummaryTokens.scale(widthPx)` = widthPx / 430.
        let designScale = widthPx / ShareSummaryTokens.canvasWidth
        let pixelRect = CGRect(
            x: cardRect.minX * imageScale,
            y: cardRect.minY * imageScale,
            width: cardRect.width * imageScale,
            height: cardRect.height * imageScale
        )
        let blurPx = blurRadiusPt * designScale
        let pad = ceil(blurPx * 3)
        let expanded = pixelRect.insetBy(dx: -pad, dy: -pad)
        let imageBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let crop = expanded.intersection(imageBounds)
        guard crop.width > 1, crop.height > 1,
              let cropped = cgImage.cropping(to: crop.integral) else { return nil }

        let localCard = CGRect(
            x: pixelRect.minX - crop.minX,
            y: pixelRect.minY - crop.minY,
            width: pixelRect.width,
            height: pixelRect.height
        ).integral
        guard localCard.width > 1, localCard.height > 1,
              let blurredCG = androidMatchedBlur(cropped: cropped, blurPx: blurPx),
              let slice = blurredCG.cropping(to: localCard) else { return nil }

        let cardW = Int(localCard.width)
        let cardH = Int(localCard.height)
        let cornerPx = cornerRadius * imageScale
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let pixelSize = CGSize(width: cardW, height: cardH)
        let plate = UIGraphicsImageRenderer(size: pixelSize, format: format).image { ctx in
            let cg = ctx.cgContext
            let bounds = CGRect(origin: .zero, size: pixelSize)
            let path = UIBezierPath(roundedRect: bounds, cornerRadius: cornerPx)
            cg.saveGState()
            path.addClip()
            UIImage(cgImage: slice, scale: 1, orientation: .up).draw(in: bounds)
            // Same two source-over white passes as Android `drawColor(GLASS_FILL)` + `drawColor(WASH)`.
            UIColor.white.withAlphaComponent(glassFillAlpha).setFill()
            path.fill()
            UIColor.white.withAlphaComponent(washAlpha).setFill()
            path.fill()
            cg.restoreGState()

            cg.saveGState()
            path.addClip()
            // Android: strokeWidth = max(1f, scale) in **pixels**.
            let stroke = max(1, designScale)
            cg.setLineWidth(stroke)
            cg.setStrokeColor(UIColor.white.withAlphaComponent(rimAlpha).cgColor)
            cg.stroke(bounds.insetBy(dx: 0.5, dy: 0.5))
            cg.setStrokeColor(UIColor.white.withAlphaComponent(catchLightAlpha).cgColor)
            cg.move(to: CGPoint(x: cornerPx * 0.35, y: 0.75))
            cg.addLine(to: CGPoint(x: CGFloat(cardW) - cornerPx * 0.35, y: 0.75))
            cg.strokePath()
            cg.restoreGState()
        }
        // Present at map point size (ImageRenderer scale = imageScale).
        guard let plateCG = plate.cgImage else { return plate }
        return UIImage(cgImage: plateCG, scale: imageScale, orientation: .up)
    }

    /// Android `ShareSummaryGlass.blurBitmap`: 1/4 scale → stack-blur → upscale.
    private static func androidMatchedBlur(cropped: CGImage, blurPx: CGFloat) -> CGImage? {
        let factor = blurDownscaleFactor
        let fullW = cropped.width
        let fullH = cropped.height
        let smallW = max(1, fullW / factor)
        let smallH = max(1, fullH / factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let smallImage = UIGraphicsImageRenderer(
            size: CGSize(width: smallW, height: smallH),
            format: format
        ).image { _ in
            UIImage(cgImage: cropped, scale: 1, orientation: .up)
                .draw(in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        }
        guard let smallCG = smallImage.cgImage else { return nil }
        let radius = max(1, min(25, Int((blurPx / CGFloat(factor)).rounded())))
        guard let blurredSmall = stackBlur(smallCG, radius: radius) else { return nil }
        let up = UIGraphicsImageRenderer(
            size: CGSize(width: fullW, height: fullH),
            format: format
        ).image { _ in
            UIImage(cgImage: blurredSmall, scale: 1, orientation: .up)
                .draw(in: CGRect(x: 0, y: 0, width: fullW, height: fullH))
        }
        return up.cgImage
    }

    /// Mario Klingemann stack blur — same algorithm as Android `ShareSummaryGlass.stackBlur`.
    private static func stackBlur(_ image: CGImage, radius: Int) -> CGImage? {
        guard radius >= 1 else { return image }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let wm = width - 1
        let hm = height - 1
        let wh = width * height
        let div = radius + radius + 1
        var r = [Int](repeating: 0, count: wh)
        var g = [Int](repeating: 0, count: wh)
        var b = [Int](repeating: 0, count: wh)
        var vmin = [Int](repeating: 0, count: max(width, height))
        var divsum = (div + 1) >> 1
        divsum *= divsum
        var dv = [Int](repeating: 0, count: 256 * divsum)
        for i in 0..<(256 * divsum) { dv[i] = i / divsum }
        var stack = [[Int]](repeating: [0, 0, 0], count: div)
        let r1 = radius + 1

        var yi = 0
        var yw = 0
        for y in 0..<height {
            var rinsum = 0, ginsum = 0, binsum = 0
            var routsum = 0, goutsum = 0, boutsum = 0
            var rsum = 0, gsum = 0, bsum = 0
            for i in -radius...radius {
                let p = (yi + min(wm, max(i, 0))) * 4
                var sir = stack[i + radius]
                sir[0] = Int(pixels[p])
                sir[1] = Int(pixels[p + 1])
                sir[2] = Int(pixels[p + 2])
                stack[i + radius] = sir
                let rbs = r1 - abs(i)
                rsum += sir[0] * rbs
                gsum += sir[1] * rbs
                bsum += sir[2] * rbs
                if i > 0 {
                    rinsum += sir[0]; ginsum += sir[1]; binsum += sir[2]
                } else {
                    routsum += sir[0]; goutsum += sir[1]; boutsum += sir[2]
                }
            }
            var stackpointer = radius
            for x in 0..<width {
                r[yi] = dv[rsum]
                g[yi] = dv[gsum]
                b[yi] = dv[bsum]
                rsum -= routsum
                gsum -= goutsum
                bsum -= boutsum
                let stackstart = stackpointer - radius + div
                var sir = stack[stackstart % div]
                routsum -= sir[0]
                goutsum -= sir[1]
                boutsum -= sir[2]
                if y == 0 { vmin[x] = min(x + radius + 1, wm) }
                let p = (yw + vmin[x]) * 4
                sir[0] = Int(pixels[p])
                sir[1] = Int(pixels[p + 1])
                sir[2] = Int(pixels[p + 2])
                stack[stackstart % div] = sir
                rinsum += sir[0]
                ginsum += sir[1]
                binsum += sir[2]
                rsum += rinsum
                gsum += ginsum
                bsum += binsum
                stackpointer = (stackpointer + 1) % div
                sir = stack[stackpointer % div]
                routsum += sir[0]
                goutsum += sir[1]
                boutsum += sir[2]
                rinsum -= sir[0]
                ginsum -= sir[1]
                binsum -= sir[2]
                stack[stackpointer % div] = sir
                yi += 1
            }
            yw += width
        }

        for x in 0..<width {
            var rinsum = 0, ginsum = 0, binsum = 0
            var routsum = 0, goutsum = 0, boutsum = 0
            var rsum = 0, gsum = 0, bsum = 0
            var yp = -radius * width
            for i in -radius...radius {
                let yi2 = max(0, yp) + x
                var sir = stack[i + radius]
                sir[0] = r[yi2]
                sir[1] = g[yi2]
                sir[2] = b[yi2]
                stack[i + radius] = sir
                let rbs = r1 - abs(i)
                rsum += r[yi2] * rbs
                gsum += g[yi2] * rbs
                bsum += b[yi2] * rbs
                if i > 0 {
                    rinsum += sir[0]; ginsum += sir[1]; binsum += sir[2]
                } else {
                    routsum += sir[0]; goutsum += sir[1]; boutsum += sir[2]
                }
                if i < hm { yp += width }
            }
            var yi2 = x
            var stackpointer = radius
            for y in 0..<height {
                let idx = yi2 * 4
                pixels[idx] = UInt8(dv[rsum])
                pixels[idx + 1] = UInt8(dv[gsum])
                pixels[idx + 2] = UInt8(dv[bsum])
                // keep alpha
                rsum -= routsum
                gsum -= goutsum
                bsum -= boutsum
                let stackstart = stackpointer - radius + div
                var sir = stack[stackstart % div]
                routsum -= sir[0]
                goutsum -= sir[1]
                boutsum -= sir[2]
                if x == 0 { vmin[y] = min(y + r1, hm) * width }
                let p = x + vmin[y]
                sir[0] = r[p]
                sir[1] = g[p]
                sir[2] = b[p]
                stack[stackstart % div] = sir
                rinsum += sir[0]
                ginsum += sir[1]
                binsum += sir[2]
                rsum += rinsum
                gsum += ginsum
                bsum += binsum
                stackpointer = (stackpointer + 1) % div
                sir = stack[stackpointer % div]
                routsum += sir[0]
                goutsum += sir[1]
                boutsum += sir[2]
                rinsum -= sir[0]
                ginsum -= sir[1]
                binsum -= sir[2]
                stack[stackpointer % div] = sir
                yi2 += width
            }
        }

        guard let out = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage() else { return nil }
        return out
    }
}

// MARK: - Page

private struct SummaryMapSharePage: View {
    let record: SavedHikingSession
    let mapImage: UIImage
    let memoLineCount: Int
    let showsWeatherLabel: Bool
    let variant: HikingRecordSummaryShareComposer.Variant

    private var s: CGFloat { ShareSummaryTokens.ptScale(for: mapImage.size.width) }

    private var showsWeather: Bool {
        showsWeatherLabel && record.weather != nil
    }

    private var cardRect: CGRect {
        let inset = ShareSummaryTokens.cardInset * s
        let height = ShareSummaryTokens.cardHeight * s
        return CGRect(
            x: inset,
            y: mapImage.size.height - inset - height,
            width: mapImage.size.width - inset * 2,
            height: height
        )
    }

    private var glassBackdrop: UIImage? {
        guard variant == .simpleColor else { return nil }
        return ShareSummaryGlassBackdrop.bake(
            mapImage: mapImage,
            cardRect: cardRect,
            cornerRadius: ShareSummaryTokens.cardRadius * s
        )
    }

    var body: some View {
        ZStack {
            // Full-bleed map under/beside the floating card (no solid MapPaper plate).
            Image(uiImage: mapImage)
                .resizable()
                .frame(width: mapImage.size.width, height: mapImage.size.height)

            // Fade is baked under the route in the snapshot (finding 2). Header sits above.

            headerBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            mapsAttribution
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

            SummaryInfoCard(
                record: record,
                scale: s,
                glassBackdrop: glassBackdrop
            )
            .padding(.horizontal, ShareSummaryTokens.cardInset * s)
            .padding(.bottom, ShareSummaryTokens.cardInset * s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: mapImage.size.width, height: mapImage.size.height)
        .clipped()
    }

    private var headerBlock: some View {
        // Gaps are separate spacers — never pad inside a fixed line-box frame (findings 3–4).
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16 * s) {
                summaryLogo
                Spacer(minLength: 16 * s)
                if showsWeather, let weather = record.weather {
                    ShareSummaryWeatherCard(
                        weather: weather,
                        scale: s,
                        maxWidth: mapImage.size.width * ShareSummaryTokens.weatherMaxWidthFraction
                    )
                }
            }
            .frame(height: ShareSummaryTokens.headerRow1Height * s, alignment: .center)

            Color.clear.frame(height: ShareSummaryTokens.headerTitleGap * s)

            // Layout frame stays headerTitleLineHeight (headerBottom / title-gap).
            // Paint lh +8pt + allowInkOverflow (topLeading) so 받침 clear without
            // shifting the left-under-logo slot.
            ShareSummaryTypeBox.text(
                record.exportCardTitle,
                size: ShareSummaryTokens.headerTitleSize * s,
                weight: .bold,
                lineHeight: (ShareSummaryTokens.headerTitleLineHeight + 8) * s,
                color: ShareSummaryTokens.inkUIColor,
                tracking: -0.2 * s,
                frameHeight: ShareSummaryTokens.headerTitleLineHeight * s,
                allowInkOverflow: true
            )
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let memo = record.memo?.trimmingCharacters(in: .whitespacesAndNewlines), !memo.isEmpty {
                Color.clear.frame(height: ShareSummaryTokens.memoGapFromTitle * s)
                let memoWidth = mapImage.size.width - ShareSummaryTokens.headerInset * 2 * s
                ShareSummaryMemoText(
                    text: memo,
                    scale: s,
                    lineCount: max(memoLineCount, 1),
                    width: memoWidth
                )
            }
        }
        .padding(.top, ShareSummaryTokens.headerTop * s)
        .padding(.horizontal, ShareSummaryTokens.headerInset * s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryLogo: some View {
        let height = ShareSummaryTokens.headerLogoHeight * s
        return Image("SansanLogoSymbol")
            .resizable()
            .aspectRatio(RouteBrandLogoMetrics.artworkAspect, contentMode: .fit)
            .frame(height: height)
    }

    /// Apple Maps credit between map and card (§13 / S10).
    /// MKMapSnapshotter does not bake legal marks into the image — we draw them.
    /// Android parity: glyph + ~1px white stroke only — no paper clearZone / no plate.
    private var mapsAttribution: some View {
        // ~1.25–1.4px stroke @3x — hard offset copies, not blur/shadow (those read as a pill).
        let halo = 0.4 * s
        let ink: Color = variant == .simpleColor
            ? Color(ShareSummaryTokens.inkUIColor).opacity(0.72)
            : Color(ShareSummaryTokens.mapTextUIColor)
        let offsets: [(CGFloat, CGFloat)] = [
            (-halo, 0), (halo, 0), (0, -halo), (0, halo),
            (-halo, -halo), (-halo, halo), (halo, -halo), (halo, halo),
        ]
        return ZStack {
            ForEach(0..<offsets.count, id: \.self) { i in
                attributionGlyphs
                    .foregroundStyle(Color.white)
                    .offset(x: offsets[i].0, y: offsets[i].1)
            }
            attributionGlyphs
                .foregroundStyle(ink)
        }
        .frame(height: ShareSummaryTokens.attributionLineHeight * s, alignment: .center)
        .frame(maxWidth: ShareSummaryTokens.attributionMaxWidth * s, alignment: .leading)
        .padding(.leading, ShareSummaryTokens.attributionX * s)
        .padding(
            .bottom,
            (ShareSummaryTokens.cardInset + ShareSummaryTokens.cardHeight + ShareSummaryTokens.attributionGapAboveCard) * s
        )
    }

    private var attributionGlyphs: some View {
        HStack(alignment: .center, spacing: ShareSummaryTokens.attributionLogoGap * s) {
            Image(systemName: "apple.logo")
                .font(.system(size: ShareSummaryTokens.attributionLogoHeight * s, weight: .medium))
                .frame(
                    width: ShareSummaryTokens.attributionLogoHeight * s,
                    height: ShareSummaryTokens.attributionLogoHeight * s
                )
            Text("지도")
                .font(.system(size: ShareSummaryTokens.attributionFontSize * s, weight: .medium))
                .tracking(0)
        }
    }
}

// MARK: - Memo (exact lh 17 + tail …)
// ImageRenderer cannot flatten UIViewRepresentable — bake Core Text into a UIImage instead.

private struct ShareSummaryMemoText: View {
    let text: String
    let scale: CGFloat
    let lineCount: Int
    let width: CGFloat

    var body: some View {
        let lines = min(ShareSummaryTokens.memoMaxLines, max(lineCount, 1))
        let height = CGFloat(lines) * ShareSummaryTokens.memoLineHeight * scale
        Image(uiImage: Self.render(text: text, width: width, height: height, scale: scale))
            .resizable()
            .interpolation(.high)
            .frame(width: width, height: height, alignment: .topLeading)
    }

    private static func render(text: String, width: CGFloat, height: CGFloat, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let size = CGSize(width: max(width, 1), height: max(height, 1))
        let font = UIFont.systemFont(ofSize: ShareSummaryTokens.memoFontSize * scale, weight: .medium)
        let lineHeight = ShareSummaryTokens.memoLineHeight * scale
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: ShareSummaryTokens.mapTextUIColor,
            .kern: ShareSummaryTokens.memoTracking * scale
        ]
        let ns = NSAttributedString(string: text, attributes: attrs)
        let typesetter = CTTypesetterCreateWithAttributedString(ns as CFAttributedString)
        let maxLines = ShareSummaryTokens.memoMaxLines
        let ellipsis = CTLineCreateWithAttributedString(
            NSAttributedString(string: "…", attributes: attrs) as CFAttributedString
        )
        var offset = 0
        var drawn: [CTLine] = []
        while offset < ns.length && drawn.count < maxLines {
            let remaining = ns.length - offset
            let isLastSlot = drawn.count == maxLines - 1
            if isLastSlot && remaining > 0 {
                let rest = ns.attributedSubstring(from: NSRange(location: offset, length: remaining))
                let full = CTLineCreateWithAttributedString(rest as CFAttributedString)
                if let truncated = CTLineCreateTruncatedLine(full, Double(size.width), .end, ellipsis) {
                    drawn.append(truncated)
                } else {
                    drawn.append(full)
                }
                break
            }
            let fit = CTTypesetterSuggestLineBreak(typesetter, offset, Double(size.width))
            if fit <= 0 { break }
            drawn.append(CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: fit)))
            offset += fit
        }
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.textMatrix = .identity
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
            for (index, line) in drawn.enumerated() {
                let top = CGFloat(index) * lineHeight
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                CTLineGetTypographicBounds(line, &ascent, &descent, nil)
                // Center glyph box in fixed lh (Trim.None); UIKit y → flipped CT y.
                let uiBaseline = top + (lineHeight - ascent - descent) / 2 + ascent
                cg.textPosition = CGPoint(x: 0, y: size.height - uiBaseline)
                CTLineDraw(line, cg)
            }
        }
    }
}

// MARK: - Fixed line box (lh = box, glyph centered, Trim.None)

private enum ShareSummaryTypeBox {
    /// Centering offset for a fixed lh box. Units beside a number must reuse the
    /// **number's** offset — otherwise (lh − unitFont.lineHeight)/2 lifts km/h/m (impl4 #1).
    static func baselineOffset(
        size: CGFloat,
        weight: UIFont.Weight,
        lineHeight: CGFloat,
        monospaced: Bool = false
    ) -> CGFloat {
        let font = monospaced
            ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : UIFont.systemFont(ofSize: size, weight: weight)
        return (lineHeight - font.lineHeight) / 2
    }

    static func attributed(
        _ string: String,
        size: CGFloat,
        weight: UIFont.Weight,
        lineHeight: CGFloat,
        color: UIColor,
        tracking: CGFloat = 0,
        monospaced: Bool = false,
        baselineOffset override: CGFloat? = nil
    ) -> AttributedString {
        let font = monospaced
            ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : UIFont.systemFont(ofSize: size, weight: weight)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        let offset = override ?? (lineHeight - font.lineHeight) / 2
        let ns = NSAttributedString(
            string: string,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph,
                .kern: tracking,
                .baselineOffset: offset
            ]
        )
        return AttributedString(ns)
    }

    @ViewBuilder
    static func text(
        _ string: String,
        size: CGFloat,
        weight: UIFont.Weight,
        lineHeight: CGFloat,
        color: UIColor,
        tracking: CGFloat = 0,
        monospaced: Bool = false,
        baselineOffset override: CGFloat? = nil,
        frameHeight: CGFloat? = nil,
        /// When true, layout height stays `frameHeight`/`lineHeight` but ink may paint
        /// outside so Hangul 받침 / descenders are not under-cropped by the line box.
        allowInkOverflow: Bool = false
    ) -> some View {
        let label = Text(
            attributed(
                string,
                size: size,
                weight: weight,
                lineHeight: lineHeight,
                color: color,
                tracking: tracking,
                monospaced: monospaced,
                baselineOffset: override
            )
        )
        let boxHeight = frameHeight ?? lineHeight
        if allowInkOverflow {
            // topLeading: layout slot stays left under logo; taller paint may
            // extend below only. `.leading` alone still vertically centers.
            Color.clear
                .frame(maxWidth: .infinity, minHeight: boxHeight, maxHeight: boxHeight, alignment: .topLeading)
                .overlay(alignment: .topLeading) {
                    label
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
        } else {
            label.frame(height: boxHeight, alignment: .center)
        }
    }
}

// MARK: - Weather

private struct ShareSummaryWeatherCard: View {
    let weather: HikingRouteWeatherSnapshot
    let scale: CGFloat
    let maxWidth: CGFloat

    private var hours: [HikingWeatherHourPoint] {
        let minScale = ShareSummaryTokens.weatherMinScale * scale
        let capacity = columnCapacity(at: minScale)
        return HikingRouteWeatherSnapshot.timelineFitting(
            weather.timelineHours,
            maximumCount: min(ShareSummaryTokens.weatherMaxColumns, capacity)
        )
    }

    /// Fit card into maxWidth; floor at weatherMinScale × layout scale.
    private var displayScale: CGFloat {
        let naturalDesign = chipWidth(hours: hours, scale: 1)
        guard naturalDesign > 0 else { return scale }
        let fitted = maxWidth / naturalDesign
        return min(scale, max(fitted, ShareSummaryTokens.weatherMinScale * scale))
    }

    var body: some View {
        let s = displayScale
        HStack(alignment: .top, spacing: ShareSummaryTokens.weatherColumnGap * s) {
            ForEach(hours) { hour in
                VStack(spacing: ShareSummaryTokens.weatherIconTempGap * s) {
                    Image(systemName: HikingRouteWeatherSnapshot.symbolName(for: hour.wmoCode))
                        .font(.system(size: ShareSummaryTokens.weatherIconSize * s, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            WeatherIconPalette.primary(for: hour.wmoCode),
                            WeatherIconPalette.secondary(for: hour.wmoCode)
                        )
                        .frame(
                            width: ShareSummaryTokens.weatherColumnWidth * s,
                            height: ShareSummaryTokens.weatherIconSize * s
                        )
                        .clipped()
                    Text(hour.formattedTemperature)
                        .font(.system(size: ShareSummaryTokens.weatherTempSize * s, weight: .semibold))
                        .foregroundStyle(Color(ShareSummaryTokens.inkUIColor))
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: ShareSummaryTokens.weatherColumnWidth * s)
                }
            }
        }
        .padding(.horizontal, ShareSummaryTokens.weatherPaddingH * s)
        .padding(.vertical, ShareSummaryTokens.weatherPaddingV * s)
        .frame(height: ShareSummaryTokens.weatherHeight * s)
        .background(Color.white, in: RoundedRectangle(cornerRadius: ShareSummaryTokens.weatherRadius * s, style: .continuous))
        .shadow(color: Color(ShareSummaryTokens.inkUIColor).opacity(0.08), radius: 0.5 * s, y: 0)
        .shadow(color: Color(ShareSummaryTokens.inkUIColor).opacity(0.08), radius: 4 * s, y: 2 * s)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func columnCapacity(at scale: CGFloat) -> Int {
        guard scale > 0, maxWidth > 0 else { return 1 }
        let column = ShareSummaryTokens.weatherColumnWidth * scale
        let gap = ShareSummaryTokens.weatherColumnGap * scale
        let pad = ShareSummaryTokens.weatherPaddingH * 2 * scale
        let count = Int(((maxWidth - pad + gap) / (column + gap)).rounded(.down))
        return max(1, min(ShareSummaryTokens.weatherMaxColumns, count))
    }

    private func chipWidth(hours: [HikingWeatherHourPoint], scale: CGFloat) -> CGFloat {
        guard !hours.isEmpty else { return 0 }
        let n = CGFloat(hours.count)
        return ShareSummaryTokens.weatherPaddingH * 2 * scale
            + ShareSummaryTokens.weatherColumnWidth * n * scale
            + ShareSummaryTokens.weatherColumnGap * max(n - 1, 0) * scale
    }
}

// MARK: - Info card

/// Android `SummaryInfoCard` shadow: glass → SHADOW2 only; grey → SHADOW1+SHADOW2.
/// Tokens mirror `ShareSummaryTokens.CARD_SHADOW*` (Compose blur ≈ SwiftUI radius×2).
private struct SummaryInfoCardShadowModifier: ViewModifier {
    let scale: CGFloat
    let glass: Bool

    private let shadow1Alpha: CGFloat = 0.10
    private let shadow1Blur: CGFloat = 32
    private let shadow1Dy: CGFloat = 12
    private let shadow2Alpha: CGFloat = 0.06
    private let shadow2Blur: CGFloat = 3
    private let shadow2Dy: CGFloat = 1

    func body(content: Content) -> some View {
        if glass {
            // JW Android: skip large 32pt ambient — gray band over map attribution.
            content
                .shadow(
                    color: Color(ShareSummaryTokens.inkUIColor).opacity(shadow2Alpha),
                    radius: shadow2Blur * scale / 2,
                    y: shadow2Dy * scale
                )
        } else {
            content
                .shadow(
                    color: Color(ShareSummaryTokens.inkUIColor).opacity(shadow1Alpha),
                    radius: shadow1Blur * scale / 2,
                    y: shadow1Dy * scale
                )
                .shadow(
                    color: Color(ShareSummaryTokens.inkUIColor).opacity(shadow2Alpha),
                    radius: shadow2Blur * scale / 2,
                    y: shadow2Dy * scale
                )
        }
    }
}

private struct SummaryInfoCard: View {
    let record: SavedHikingSession
    let scale: CGFloat
    /// Pre-baked liquid-glass plate for Simple Color; nil → opaque white (Simple Grey).
    var glassBackdrop: UIImage? = nil

    private var elevationSamples: [HikingElevationChartSample] {
        if let stored = record.session.elevationProfile, stored.count >= 2 {
            return stored
        }
        return HikingSessionMetrics.elevationProfileSamples(from: record.session.points).map {
            HikingElevationChartSample(id: $0.id, distanceMeters: $0.distanceMeters, altitude: $0.altitude)
        }
    }

    private var heartSamples: [HikingHeartRateChartSample] {
        if let stored = record.session.heartRateProfile, stored.count >= 2 {
            return stored
        }
        return HikingSessionMetrics.heartRateProfileSamples(
            from: record.session.points,
            heartRateSamples: record.session.heartRateSamples
        ).map {
            HikingHeartRateChartSample(id: $0.id, distanceMeters: $0.distanceMeters, bpm: $0.bpm)
        }
    }

    /// Peak elevation from profile samples — current app meaning of 「고도 N m」.
    private var maxElevation: Int {
        Int((elevationSamples.map(\.altitude).max() ?? 0).rounded())
    }

    private var heartStats: (average: Int, minimum: Int, maximum: Int)? {
        let values = heartSamples.map(\.bpm)
        guard let minValue = values.min(), let maxValue = values.max(), !values.isEmpty else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        return (Int(average.rounded()), Int(minValue.rounded()), Int(maxValue.rounded()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ShareSummaryTokens.cardBlockGap * scale) {
            heroRow
                .padding(.horizontal, ShareSummaryTokens.cardPaddingH * scale)

            divider

            metricsRow
                .padding(.horizontal, ShareSummaryTokens.cardPaddingH * scale)
            metaRow
                .padding(.horizontal, ShareSummaryTokens.cardPaddingH * scale)
            chartBlock
                .padding(.horizontal, ShareSummaryTokens.cardPaddingH * scale)
        }
        .padding(.top, ShareSummaryTokens.cardPaddingTop * scale)
        .padding(.bottom, ShareSummaryTokens.cardPaddingBottom * scale)
        .frame(height: ShareSummaryTokens.cardHeight * scale, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(
                cornerRadius: ShareSummaryTokens.cardRadius * scale,
                style: .continuous
            )
            if let glassBackdrop {
                Image(uiImage: glassBackdrop)
                    .resizable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(shape)
            } else {
                Color.white.clipShape(shape)
            }
        }
        // Android SummaryInfoCard (JW): skip large CARD_SHADOW1 on glass — gray band over map.
        // Simple Grey keeps both shadows; Simple Color keeps only tight SHADOW2.
        .modifier(SummaryInfoCardShadowModifier(scale: scale, glass: glassBackdrop != nil))
    }

    private var heroRow: some View {
        let heroLH = ShareSummaryTokens.heroLineHeight * scale
        let heroSize = ShareSummaryTokens.heroSize * scale
        let numberBaseline = ShareSummaryTypeBox.baselineOffset(
            size: heroSize,
            weight: .light,
            lineHeight: heroLH,
            monospaced: true
        )
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: ShareSummaryTokens.cardLabelGap * scale) {
                ShareSummaryTypeBox.text(
                    "거리",
                    size: ShareSummaryTokens.labelSize * scale,
                    weight: .medium,
                    lineHeight: ShareSummaryTokens.labelLineHeight * scale,
                    color: ShareSummaryTokens.ink2UIColor
                )
                // lastTextBaseline + shared number baselineOffset (impl4 #1 unit regression).
                HStack(alignment: .lastTextBaseline, spacing: ShareSummaryTokens.heroUnitGap * scale) {
                    ShareSummaryTypeBox.text(
                        record.distanceValueText,
                        size: heroSize,
                        weight: .light,
                        lineHeight: heroLH,
                        color: ShareSummaryTokens.inkUIColor,
                        tracking: -1.4 * scale,
                        monospaced: true,
                        baselineOffset: numberBaseline
                    )
                    ShareSummaryTypeBox.text(
                        record.distanceUnitText,
                        size: ShareSummaryTokens.heroUnitSize * scale,
                        weight: .regular,
                        lineHeight: heroLH,
                        color: ShareSummaryTokens.ink2UIColor,
                        baselineOffset: numberBaseline,
                        frameHeight: heroLH
                    )
                }
                .frame(height: heroLH, alignment: .center)
            }

            timeline
                .padding(.top, (ShareSummaryTokens.timelineFirstRowTop - ShareSummaryTokens.cardPaddingTop) * scale)
                .padding(.leading, (ShareSummaryTokens.timelineDotX - ShareSummaryTokens.cardInset - ShareSummaryTokens.cardPaddingH) * scale)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeline: some View {
        let start = timeLabel(record.startedScheduleParts)
        let end = timeLabel(record.endedScheduleParts)
        let dot = ShareSummaryTokens.timelineDot * scale
        let line = ShareSummaryTokens.timelineLine * scale
        let row = ShareSummaryTokens.timeLineHeight * scale
        let gap = ShareSummaryTokens.timelineRowGap * scale
        return VStack(alignment: .leading, spacing: 0) {
            timelineRow(dot: dot, text: start, rowHeight: row, fill: Color(ShareSummaryTokens.accentUIColor))
            Color.clear.frame(height: gap)
            HStack(spacing: ShareSummaryTokens.timelineTimeGap * scale) {
                Rectangle()
                    .fill(Color(ShareSummaryTokens.trackUIColor))
                    .frame(width: max(1 * scale, 1), height: line)
                    .frame(width: dot, alignment: .center)
                Spacer(minLength: 0)
            }
            Color.clear.frame(height: gap)
            timelineRow(dot: dot, text: end, rowHeight: row, fill: Color(ShareSummaryTokens.inkUIColor))
        }
    }

    private func timelineRow(dot: CGFloat, text: String, rowHeight: CGFloat, fill: Color) -> some View {
        HStack(alignment: .center, spacing: ShareSummaryTokens.timelineTimeGap * scale) {
            Circle()
                .fill(fill)
                .frame(width: dot, height: dot)
            ShareSummaryTypeBox.text(
                text,
                size: ShareSummaryTokens.timeSize * scale,
                weight: .regular,
                lineHeight: rowHeight,
                color: ShareSummaryTokens.inkUIColor,
                monospaced: true
            )
            .lineLimit(1)
        }
        .frame(height: rowHeight, alignment: .center)
    }

    private var metricsRow: some View {
        HStack(alignment: .top, spacing: ShareSummaryTokens.cardColumnGap * scale) {
            metricColumn(label: "시간") {
                durationMetric(record.formattedDurationCompact)
            }
            metricColumn(label: "상승") {
                metricValue(record.elevationValueText, unit: "m")
            }
            metricColumn(label: "평균속도") {
                metricValue(record.averageSpeedValueText, unit: record.averageSpeedUnitText)
            }
        }
    }

    private var metaRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: ShareSummaryTokens.cardColumnGap * scale) {
            metaItem(value: record.stepCountValueText, unit: "걸음")
                .frame(width: ShareSummaryTokens.cardColumnWidth * scale, alignment: .leading)
            metaItem(value: record.caloriesValueText, unit: "kcal")
                .frame(width: ShareSummaryTokens.cardColumnWidth * scale, alignment: .leading)
            metaItem(value: "\(maxElevation)", unit: "m", label: "고도")
                .frame(width: ShareSummaryTokens.cardColumnWidth * scale, alignment: .leading)
        }
    }

    private var chartBlock: some View {
        VStack(alignment: .leading, spacing: ShareSummaryTokens.graphGapAbove * scale) {
            legendRow
            SummaryChartCanvas(elevation: elevationSamples, heartRate: heartSamples, scale: scale)
                .frame(height: ShareSummaryTokens.graphHeight * scale)
        }
    }

    private var legendRow: some View {
        HStack(spacing: 0) {
            // Bake #FF8D28 via UIColor so ImageRenderer/glass cannot grey the swatch.
            Image(uiImage: ShareSummaryElevLegendSwatch.image(
                width: ShareSummaryTokens.graphLegendSwatchWidth * scale,
                height: max(ShareSummaryTokens.graphLegendElevHeight * scale, 2 * scale)
            ))
            .frame(
                width: ShareSummaryTokens.graphLegendSwatchWidth * scale,
                height: max(ShareSummaryTokens.graphLegendElevHeight * scale, 2 * scale)
            )
            ShareSummaryTypeBox.text(
                "고도",
                size: ShareSummaryTokens.legendSize * scale,
                weight: .regular,
                lineHeight: ShareSummaryTokens.legendLineHeight * scale,
                color: ShareSummaryTokens.ink2UIColor
            )
            .padding(.leading, ShareSummaryTokens.graphLegendGap * scale)

            if let heartStats {
                Color.clear.frame(width: ShareSummaryTokens.graphLegendBlockGap * scale)
                RoundedRectangle(cornerRadius: 0.5 * scale, style: .continuous)
                    .fill(Color(ShareSummaryTokens.chartHRUIColor))
                    .frame(
                        width: ShareSummaryTokens.graphLegendSwatchWidth * scale,
                        height: ShareSummaryTokens.graphLegendHRHeight * scale
                    )
                ShareSummaryTypeBox.text(
                    "심박",
                    size: ShareSummaryTokens.legendSize * scale,
                    weight: .regular,
                    lineHeight: ShareSummaryTokens.legendLineHeight * scale,
                    color: ShareSummaryTokens.ink2UIColor
                )
                .padding(.leading, ShareSummaryTokens.graphLegendGap * scale)
                ShareSummaryTypeBox.text(
                    "\(heartStats.average)",
                    size: ShareSummaryTokens.legendSize * scale,
                    weight: .medium,
                    lineHeight: ShareSummaryTokens.legendLineHeight * scale,
                    color: ShareSummaryTokens.inkUIColor,
                    monospaced: true
                )
                .padding(.leading, 4 * scale)
                ShareSummaryTypeBox.text(
                    "\(heartStats.minimum)–\(heartStats.maximum)",
                    size: ShareSummaryTokens.legendSize * scale,
                    weight: .regular,
                    lineHeight: ShareSummaryTokens.legendLineHeight * scale,
                    color: ShareSummaryTokens.ink2UIColor,
                    monospaced: true
                )
                .padding(.leading, 4 * scale)
            }
            Spacer(minLength: 0)
        }
        .frame(height: ShareSummaryTokens.legendLineHeight * scale, alignment: .center)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(ShareSummaryTokens.hairlineUIColor))
            .frame(height: ShareSummaryTokens.hairlineWidth(scale: scale))
            .frame(maxWidth: .infinity)
    }

    private func metricColumn<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: ShareSummaryTokens.cardLabelGap * scale) {
            ShareSummaryTypeBox.text(
                label,
                size: ShareSummaryTokens.labelSize * scale,
                weight: .medium,
                lineHeight: ShareSummaryTokens.labelLineHeight * scale,
                color: ShareSummaryTokens.ink2UIColor
            )
            // Line box stays full metric lh — never shrink the box with the value (finding 1→2 cascade).
            content()
                .frame(height: ShareSummaryTokens.metricLineHeight * scale, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: ShareSummaryTokens.cardColumnWidth * scale, alignment: .leading)
    }

    /// Scale only this column when its measured width overflows 106pt (S1).
    private func metricOverflowScale(neededWidth: CGFloat) -> CGFloat {
        let available = ShareSummaryTokens.cardColumnWidth * scale
        guard neededWidth > available, neededWidth > 0 else { return 1 }
        return max(ShareSummaryTokens.metricMinScale, available / neededWidth)
    }

    private func metricTextWidth(
        _ text: String,
        size: CGFloat,
        weight: UIFont.Weight,
        tracking: CGFloat
    ) -> CGFloat {
        let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: tracking
        ]
        return ceil((text as NSString).size(withAttributes: attrs).width)
    }

    private func metricValue(_ value: String, unit: String) -> some View {
        let valueSize = ShareSummaryTokens.metricSize * scale
        let unitSize = ShareSummaryTokens.metricUnitSize * scale
        let gap = ShareSummaryTokens.metricUnitGap * scale
        let natural = metricTextWidth(value, size: valueSize, weight: .light, tracking: -0.5 * scale)
            + gap
            + metricTextWidth(unit, size: unitSize, weight: .regular, tracking: 0)
        let fit = metricOverflowScale(neededWidth: natural)
        let valueLH = ShareSummaryTokens.metricLineHeight * scale
        let numberBaseline = ShareSummaryTypeBox.baselineOffset(
            size: valueSize * fit,
            weight: .light,
            lineHeight: valueLH,
            monospaced: true
        )
        return HStack(alignment: .lastTextBaseline, spacing: ShareSummaryTokens.metricUnitGap * scale * fit) {
            ShareSummaryTypeBox.text(
                value,
                size: valueSize * fit,
                weight: .light,
                lineHeight: valueLH,
                color: ShareSummaryTokens.inkUIColor,
                tracking: -0.5 * scale * fit,
                monospaced: true,
                baselineOffset: numberBaseline
            )
            ShareSummaryTypeBox.text(
                unit,
                size: unitSize * fit,
                weight: .regular,
                lineHeight: valueLH,
                color: ShareSummaryTokens.ink2UIColor,
                baselineOffset: numberBaseline,
                frameHeight: valueLH
            )
        }
        .lineLimit(1)
    }

    private func durationMetric(_ compact: String) -> some View {
        let parts = durationParts(compact)
        var natural: CGFloat = 0
        for (index, part) in parts.enumerated() {
            if index > 0 {
                natural += durationGap(before: parts[index - 1], current: part) * scale
            }
            let size = (part.isUnit ? ShareSummaryTokens.metricUnitSize : ShareSummaryTokens.metricSize) * scale
            let tracking = part.isUnit ? 0 : -0.5 * scale
            natural += metricTextWidth(
                part.text,
                size: size,
                weight: part.isUnit ? .regular : .light,
                tracking: tracking
            )
        }
        let fit = metricOverflowScale(neededWidth: natural)
        let valueLH = ShareSummaryTokens.metricLineHeight * scale
        let numberBaseline = ShareSummaryTypeBox.baselineOffset(
            size: ShareSummaryTokens.metricSize * scale * fit,
            weight: .light,
            lineHeight: valueLH,
            monospaced: true
        )
        return HStack(alignment: .lastTextBaseline, spacing: 0) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Color.clear.frame(
                        width: durationGap(before: parts[index - 1], current: part) * scale * fit,
                        height: 1
                    )
                }
                ShareSummaryTypeBox.text(
                    part.text,
                    size: (part.isUnit ? ShareSummaryTokens.metricUnitSize : ShareSummaryTokens.metricSize) * scale * fit,
                    weight: part.isUnit ? .regular : .light,
                    lineHeight: valueLH,
                    color: part.isUnit ? ShareSummaryTokens.ink2UIColor : ShareSummaryTokens.inkUIColor,
                    tracking: part.isUnit ? 0 : -0.5 * scale * fit,
                    monospaced: true,
                    baselineOffset: numberBaseline,
                    frameHeight: valueLH
                )
            }
        }
        .lineLimit(1)
    }

    private func durationGap(before: DurationPart, current: DurationPart) -> CGFloat {
        if before.isUnit && !current.isUnit {
            return ShareSummaryTokens.metricUnitTrailing
        }
        return ShareSummaryTokens.metricUnitGap
    }

    private func metaItem(value: String, unit: String, label: String? = nil) -> some View {
        let lh = ShareSummaryTokens.metaLineHeight * scale
        return HStack(alignment: .firstTextBaseline, spacing: ShareSummaryTokens.metaUnitGap * scale) {
            if let label {
                ShareSummaryTypeBox.text(
                    label,
                    size: ShareSummaryTokens.metaSize * scale,
                    weight: .regular,
                    lineHeight: lh,
                    color: ShareSummaryTokens.ink2UIColor
                )
            }
            ShareSummaryTypeBox.text(
                value,
                size: ShareSummaryTokens.metaSize * scale,
                weight: .medium,
                lineHeight: lh,
                color: ShareSummaryTokens.inkUIColor,
                monospaced: true
            )
            ShareSummaryTypeBox.text(
                unit,
                size: ShareSummaryTokens.metaSize * scale,
                weight: .regular,
                lineHeight: lh,
                color: ShareSummaryTokens.ink2UIColor
            )
        }
        .frame(height: lh, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeLabel(_ parts: ScheduleDateParts?) -> String {
        guard let parts else { return "—" }
        // JW: Korean order 「오후 7:37」 (period then h:mm), matching Android DateText.time.
        if let period = parts.periodText, !period.isEmpty {
            return "\(period) \(parts.timeText)"
        }
        return parts.timeText
    }

    private struct DurationPart {
        let text: String
        let isUnit: Bool
    }

    private func durationParts(_ compact: String) -> [DurationPart] {
        // "1h 47m" or "47:30"
        if compact.contains("h") || (compact.contains("m") && compact.contains(" ")) {
            var parts: [DurationPart] = []
            for token in compact.split(separator: " ") {
                let s = String(token)
                if s.hasSuffix("h"), !s.dropLast().isEmpty {
                    parts.append(.init(text: String(s.dropLast()), isUnit: false))
                    parts.append(.init(text: "h", isUnit: true))
                } else if s.hasSuffix("m"), !s.dropLast().isEmpty {
                    parts.append(.init(text: String(s.dropLast()), isUnit: false))
                    parts.append(.init(text: "m", isUnit: true))
                } else {
                    parts.append(.init(text: s, isUnit: false))
                }
            }
            return parts
        }
        return [.init(text: compact, isUnit: false)]
    }
}

// MARK: - Chart

private struct SummaryChartCanvas: View {
    let elevation: [HikingElevationChartSample]
    let heartRate: [HikingHeartRateChartSample]
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            let elevationMax = max(elevation.map(\.altitude).max() ?? 1, 1)
            let heartMax = max(heartRate.map(\.bpm).max() ?? 160, 80)
            let heartMin = 40.0
            let distanceMax = max(
                elevation.map(\.distanceMeters).max() ?? 0,
                heartRate.map(\.distanceMeters).max() ?? 0,
                1
            )

            func point(distance: Double, value: Double, lower: Double, upper: Double) -> CGPoint {
                let x = size.width * CGFloat(distance / distanceMax)
                let span = max(upper - lower, 1)
                let y = size.height - size.height * CGFloat((value - lower) / span)
                return CGPoint(x: x, y: min(max(y, 0), size.height))
            }

            let hair = ShareSummaryTokens.hairlineWidth(scale: scale)
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: size.height - hair / 2))
            baseline.addLine(to: CGPoint(x: size.width, y: size.height - hair / 2))
            context.stroke(baseline, with: .color(Color(ShareSummaryTokens.hairlineUIColor)), lineWidth: hair)

            // Draw order (spec-glass3 §9): elev fill → HR line → elev line (elev on top when overlapping).
            var elevFirst: CGPoint?
            if elevation.count >= 2 {
                var area = Path()
                let first = point(distance: elevation[0].distanceMeters, value: elevation[0].altitude, lower: 0, upper: elevationMax)
                elevFirst = first
                area.move(to: CGPoint(x: first.x, y: size.height))
                area.addLine(to: first)
                for sample in elevation.dropFirst() {
                    area.addLine(to: point(distance: sample.distanceMeters, value: sample.altitude, lower: 0, upper: elevationMax))
                }
                if let last = elevation.last {
                    let end = point(distance: last.distanceMeters, value: last.altitude, lower: 0, upper: elevationMax)
                    area.addLine(to: CGPoint(x: end.x, y: size.height))
                }
                area.closeSubpath()
                // #FF8D28 @ 15% flat fill (JW / elevation-color-v2 white card).
                context.fill(
                    area,
                    with: .color(Color(ShareSummaryTokens.chartElevUIColor).opacity(ShareSummaryTokens.chartElevFillAlpha))
                )
            }

            if heartRate.count >= 2 {
                var line = Path()
                let first = point(distance: heartRate[0].distanceMeters, value: heartRate[0].bpm, lower: heartMin, upper: heartMax)
                line.move(to: first)
                for sample in heartRate.dropFirst() {
                    line.addLine(to: point(distance: sample.distanceMeters, value: sample.bpm, lower: heartMin, upper: heartMax))
                }
                context.stroke(
                    line,
                    with: .color(Color(ShareSummaryTokens.chartHRUIColor)),
                    lineWidth: ShareSummaryTokens.graphHRWidth * scale
                )
            }

            if elevation.count >= 2, let first = elevFirst {
                var line = Path()
                line.move(to: first)
                for sample in elevation.dropFirst() {
                    line.addLine(to: point(distance: sample.distanceMeters, value: sample.altitude, lower: 0, upper: elevationMax))
                }
                context.stroke(
                    line,
                    with: .color(Color(ShareSummaryTokens.chartElevUIColor)),
                    lineWidth: ShareSummaryTokens.graphElevWidth * scale
                )
            }
        }
    }
}

#endif
