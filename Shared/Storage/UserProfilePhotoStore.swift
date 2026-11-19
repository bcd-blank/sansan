//
//  UserProfilePhotoStore.swift
//  Shared
//

#if os(iOS)

import UIKit

enum UserProfilePhotoStore {
    private static let maxPixel: CGFloat = 512

    static var fileURL: URL? {
        UserDataPaths.profilePhotoFileURL
    }

    static var hasPhoto: Bool {
        guard let url = fileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    @discardableResult
    static func save(_ image: UIImage) throws -> URL {
        guard let url = fileURL else { throw StoreError.noActiveUser }
        let prepared = UIImage.prepareProfilePhoto(image, maxPixel: maxPixel)
        guard let data = prepared.jpegData(compressionQuality: 0.88) else {
            throw StoreError.encodingFailed
        }
        try data.write(to: url, options: [.atomic])
        return url
    }

    static func loadImage() -> UIImage? {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func deletePhoto() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    enum StoreError: Error {
        case noActiveUser
        case encodingFailed
    }
}

private extension UIImage {
    static func prepareProfilePhoto(_ image: UIImage, maxPixel: CGFloat) -> UIImage {
        let normalized = image.normalizedUp()
        let width = normalized.size.width
        let height = normalized.size.height
        let side = min(width, height)
        let cropOrigin = CGPoint(x: (width - side) / 2, y: (height - side) / 2)
        let cropRect = CGRect(origin: cropOrigin, size: CGSize(width: side, height: side))
        let pixelCrop = CGRect(
            x: cropRect.origin.x * normalized.scale,
            y: cropRect.origin.y * normalized.scale,
            width: cropRect.width * normalized.scale,
            height: cropRect.height * normalized.scale
        )

        guard let cgImage = normalized.cgImage?.cropping(to: pixelCrop) else {
            return normalized
        }

        var squared = UIImage(cgImage: cgImage, scale: normalized.scale, orientation: .up)
        guard side > maxPixel else { return squared }

        let target = CGSize(width: maxPixel, height: maxPixel)
        let renderer = UIGraphicsImageRenderer(size: target)
        squared = renderer.image { _ in
            squared.draw(in: CGRect(origin: .zero, size: target))
        }
        return squared
    }

    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

#endif
