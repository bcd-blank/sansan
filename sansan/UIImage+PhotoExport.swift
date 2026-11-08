//
//  UIImage+PhotoExport.swift
//  sansan
//

#if os(iOS)

import UIKit

extension UIImage {
    /// PhotoKit 저장 시 불필요한 알파 채널 경고와 파일·메모리 낭비를 줄입니다.
    func preparedForPhotoLibraryExport() -> UIImage {
        guard let cgImage else { return self }
        switch cgImage.alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst:
            return self
        default:
            break
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemGroupedBackground.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            draw(at: .zero)
        }
    }
}

#endif
