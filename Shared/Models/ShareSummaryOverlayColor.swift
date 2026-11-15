//
//  ShareSummaryOverlayColor.swift
//  Shared
//
//  Dominant-color tuning for share-summary text-area scrims.
//  Layout/geometry stay in HikingRecordSummaryShareComposer — this file is color math only.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Tuned overlay fill derived from a summary map image (or a fallback).
struct ShareSummaryOverlayFill: Equatable {
    /// sRGB 0…1
    var red: Double
    var green: Double
    var blue: Double
    /// Whether the gray-map fallback hex was used.
    var usedFallback: Bool
    /// Final lightness percent applied (26 or 22).
    var lightnessPercent: Double
}

enum ShareSummaryOverlayColor {
    /// Builds the overlay RGB from an extracted hue/saturation (fractions 0…1 for S).
    static func fill(
        hueDegrees: Double,
        saturation: Double,
        forceFallback: Bool = false
    ) -> ShareSummaryOverlayFill {
        let extractedSPercent = saturation * 100
        if forceFallback || extractedSPercent < ShareSummaryOverlayTokens.fallbackSaturationBelowPercent {
            return fillFromFallbackHex()
        }

        let clampedS = min(
            max(extractedSPercent, ShareSummaryOverlayTokens.saturationClampMinPercent),
            ShareSummaryOverlayTokens.saturationClampMaxPercent
        ) / 100

        let hue = normalizedHue(hueDegrees)
        var lightness = ShareSummaryOverlayTokens.lightnessPercent / 100
        var rgb = hslToRGB(h: hue, s: clampedS, l: lightness)
        if contrastRatio(foregroundWhiteAgainst: rgb) < ShareSummaryOverlayTokens.minimumContrastRatio {
            lightness = ShareSummaryOverlayTokens.lightnessWeakContrastPercent / 100
            rgb = hslToRGB(h: hue, s: clampedS, l: lightness)
        }

        return ShareSummaryOverlayFill(
            red: rgb.r,
            green: rgb.g,
            blue: rgb.b,
            usedFallback: false,
            lightnessPercent: lightness * 100
        )
    }

    static func fillFromFallbackHex() -> ShareSummaryOverlayFill {
        let rgb = hexToRGB(ShareSummaryOverlayTokens.fallbackHex)
        return ShareSummaryOverlayFill(
            red: rgb.r,
            green: rgb.g,
            blue: rgb.b,
            usedFallback: true,
            lightnessPercent: ShareSummaryOverlayTokens.lightnessPercent
        )
    }

    /// Average chromatic sample → tuned fill. Gray / empty samples fall back.
    static func fill(fromRGBSamples samples: [(r: Double, g: Double, b: Double)]) -> ShareSummaryOverlayFill {
        guard let hs = dominantHueSaturation(from: samples) else {
            return fillFromFallbackHex()
        }
        return fill(hueDegrees: hs.h, saturation: hs.s)
    }

    // MARK: - Hue / saturation from samples

    /// Saturation-weighted circular mean of hue; ignores near-black / near-white / gray pixels.
    static func dominantHueSaturation(
        from samples: [(r: Double, g: Double, b: Double)]
    ) -> (h: Double, s: Double)? {
        var sinSum = 0.0
        var cosSum = 0.0
        var satSum = 0.0
        var weightSum = 0.0

        for sample in samples {
            let hsl = rgbToHSL(r: sample.r, g: sample.g, b: sample.b)
            // Skip near-gray and extreme L so map paper/labels don't dominate.
            guard hsl.s >= 0.08, hsl.l > 0.08, hsl.l < 0.92 else { continue }
            let weight = Double(hsl.s)
            let radians = hsl.h * .pi / 180
            sinSum += sin(radians) * weight
            cosSum += cos(radians) * weight
            satSum += hsl.s * weight
            weightSum += weight
        }

        guard weightSum > 0 else { return nil }
        let hue = normalizedHue(atan2(sinSum, cosSum) * 180 / .pi)
        let sat = satSum / weightSum
        return (hue, sat)
    }

    // MARK: - Color space helpers

    static func rgbToHSL(r: Double, g: Double, b: Double) -> (h: Double, s: Double, l: Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let l = (maxC + minC) / 2
        let delta = maxC - minC
        guard delta > 1e-9 else { return (0, 0, l) }

        let s = l > 0.5 ? delta / (2 - maxC - minC) : delta / (maxC + minC)
        let hSector: Double
        if maxC == r {
            hSector = (g - b) / delta
        } else if maxC == g {
            hSector = (b - r) / delta + 2
        } else {
            hSector = (r - g) / delta + 4
        }
        return (normalizedHue(hSector * 60), min(max(s, 0), 1), min(max(l, 0), 1))
    }

    static func hslToRGB(h: Double, s: Double, l: Double) -> (r: Double, g: Double, b: Double) {
        let hue = normalizedHue(h)
        if s <= 1e-9 {
            return (l, l, l)
        }
        func hue2rgb(_ p: Double, _ q: Double, _ tIn: Double) -> Double {
            var t = tIn
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        let hk = hue / 360
        return (
            hue2rgb(p, q, hk + 1.0 / 3),
            hue2rgb(p, q, hk),
            hue2rgb(p, q, hk - 1.0 / 3)
        )
    }

    static func hexToRGB(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            return (0.19, 0.39, 0.35) // #306458-ish safe default
        }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    static func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
        func channel(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    static func contrastRatio(foregroundWhiteAgainst rgb: (r: Double, g: Double, b: Double)) -> Double {
        let l1 = 1.0 // white
        let l2 = relativeLuminance(r: rgb.r, g: rgb.g, b: rgb.b)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    static func normalizedHue(_ degrees: Double) -> Double {
        var h = degrees.truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        return h
    }
}

#if canImport(UIKit) && os(iOS)
extension ShareSummaryOverlayColor {
    /// Samples the map bitmap and returns the tuned overlay UIColor.
    static func uiColor(from image: UIImage, maxSamples: Int = 2_048) -> UIColor {
        let fill = fill(from: image, maxSamples: maxSamples)
        return UIColor(red: fill.red, green: fill.green, blue: fill.blue, alpha: 1)
    }

    static func fill(from image: UIImage, maxSamples: Int = 2_048) -> ShareSummaryOverlayFill {
        let samples = sampleRGB(from: image, maxSamples: maxSamples)
        return fill(fromRGBSamples: samples)
    }

    static func sampleRGB(from image: UIImage, maxSamples: Int) -> [(r: Double, g: Double, b: Double)] {
        guard let cgImage = image.cgImage else { return [] }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return [] }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let total = width * height
        let step = max(1, total / max(1, maxSamples))
        var samples: [(r: Double, g: Double, b: Double)] = []
        samples.reserveCapacity(min(maxSamples, total / step + 1))

        var index = 0
        while index < total {
            let offset = index * bytesPerPixel
            let a = Double(data[offset + 3]) / 255
            if a > 0.05 {
                // Un-premultiply when needed.
                let r = Double(data[offset]) / 255 / a
                let g = Double(data[offset + 1]) / 255 / a
                let b = Double(data[offset + 2]) / 255 / a
                samples.append((min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1)))
            }
            index += step
        }
        return samples
    }
}
#endif
