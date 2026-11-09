//
//  HikingRouteSnapshotImageQuality.swift
//  Shared
//
//  목록 썸네일·지도 캡처가 Metal 미렌더로 비었는지 판별합니다.
//

#if os(iOS)

import UIKit

enum HikingRouteSnapshotImageQuality {
    /// Metal 미렌더(검정) 또는 타일·경로 없이 단색(라이트 systemBackground)인 캡처.
    static func isEffectivelyBlank(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return true }

        let sampleWidth = min(cgImage.width, 24)
        let sampleHeight = min(cgImage.height, 24)
        guard sampleWidth > 0, sampleHeight > 0 else { return true }

        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        guard let context = CGContext(
            data: &pixels,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: sampleWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return true }

        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight)
        )

        let pixelCount = sampleWidth * sampleHeight
        var luminanceTotal = 0
        var luminanceMin = 255
        var luminanceMax = 0
        for index in 0..<pixelCount {
            let offset = index * 4
            let luminance = (Int(pixels[offset])
                + Int(pixels[offset + 1])
                + Int(pixels[offset + 2])) / 3
            luminanceTotal += luminance
            luminanceMin = min(luminanceMin, luminance)
            luminanceMax = max(luminanceMax, luminance)
        }

        let mean = luminanceTotal / max(pixelCount, 1)
        // 아직 그려지지 않은 Metal 뷰는 거의 검정으로 나옵니다.
        if mean < 24 { return true }
        // 타일·경로가 없으면 drawHierarchy가 단색 배경만 남깁니다(라이트 모드 빈 썸네일).
        if luminanceMax - luminanceMin <= 8 { return true }
        return false
    }
}

#endif
