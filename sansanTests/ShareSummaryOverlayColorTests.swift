//
//  ShareSummaryOverlayColorTests.swift
//  sansanTests
//

import XCTest
@testable import sansan

final class ShareSummaryOverlayColorTests: XCTestCase {
    func testFallbackWhenExtractedSaturationBelow20Percent() {
        let fill = ShareSummaryOverlayColor.fill(hueDegrees: 160, saturation: 0.15)
        XCTAssertTrue(fill.usedFallback)
        let expected = ShareSummaryOverlayColor.hexToRGB(ShareSummaryOverlayTokens.fallbackHex)
        XCTAssertEqual(fill.red, expected.r, accuracy: 0.001)
        XCTAssertEqual(fill.green, expected.g, accuracy: 0.001)
        XCTAssertEqual(fill.blue, expected.b, accuracy: 0.001)
    }

    func testSaturationClampedTo25Through45() {
        let low = ShareSummaryOverlayColor.fill(hueDegrees: 150, saturation: 0.22)
        let high = ShareSummaryOverlayColor.fill(hueDegrees: 150, saturation: 0.80)
        XCTAssertFalse(low.usedFallback)
        XCTAssertFalse(high.usedFallback)

        let lowHSL = ShareSummaryOverlayColor.rgbToHSL(r: low.red, g: low.green, b: low.blue)
        let highHSL = ShareSummaryOverlayColor.rgbToHSL(r: high.red, g: high.green, b: high.blue)
        XCTAssertEqual(lowHSL.s * 100, ShareSummaryOverlayTokens.saturationClampMinPercent, accuracy: 1.5)
        XCTAssertEqual(highHSL.s * 100, ShareSummaryOverlayTokens.saturationClampMaxPercent, accuracy: 1.5)
    }

    func testKeepsHueAndDefaultLightness26() {
        let fill = ShareSummaryOverlayColor.fill(hueDegrees: 168, saturation: 0.40)
        XCTAssertFalse(fill.usedFallback)
        XCTAssertEqual(fill.lightnessPercent, ShareSummaryOverlayTokens.lightnessPercent, accuracy: 0.01)
        let hsl = ShareSummaryOverlayColor.rgbToHSL(r: fill.red, g: fill.green, b: fill.blue)
        XCTAssertEqual(hsl.h, 168, accuracy: 2)
        XCTAssertEqual(hsl.l * 100, ShareSummaryOverlayTokens.lightnessPercent, accuracy: 1.5)
    }

    func testGraySamplesUseFallbackHex() {
        let samples = Array(repeating: (r: 0.55, g: 0.55, b: 0.56), count: 64)
        let fill = ShareSummaryOverlayColor.fill(fromRGBSamples: samples)
        XCTAssertTrue(fill.usedFallback)
    }

    func testChromaticSamplesProduceNonFallback() {
        // Strong teal-green map-like samples.
        let samples = (0..<64).map { _ in (r: 0.25, g: 0.55, b: 0.48) }
        let fill = ShareSummaryOverlayColor.fill(fromRGBSamples: samples)
        XCTAssertFalse(fill.usedFallback)
    }

    func testOverlayOpacityTokenIs56Percent() {
        XCTAssertEqual(ShareSummaryOverlayTokens.overlayOpacity, 0.56, accuracy: 0.0001)
    }

    func testFallbackHexIs306458() {
        XCTAssertEqual(ShareSummaryOverlayTokens.fallbackHex.lowercased(), "306458")
    }
}
