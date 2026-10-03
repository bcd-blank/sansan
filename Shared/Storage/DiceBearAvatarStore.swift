//
//  DiceBearAvatarStore.swift
//  Shared
//
//  DiceBear HTTP API — Dylan 스타일 기본 아바타.
//  6종 미리보기는 앱 리소스. 「새로 불러오기」는 같은 머리·수염으로 새 seed를 받아 조합을 새로 만듭니다.
//  https://www.dicebear.com/styles/dylan/
//

#if os(iOS)

import UIKit

enum DiceBearAvatarStore {
    static let styleName = "dylan"
    static let apiVersion = "10.x"
    static let cacheFilename = HikingStorageLayout.avatarFilename

    static var cacheFileURL: URL? {
        guard let root = UserDataPaths.activeUserRoot else { return nil }
        return HikingStorageLayout.avatarURL(in: root)
    }

    static func loadCachedImage() -> UIImage? {
        guard let root = UserDataPaths.activeUserRoot,
              let url = HikingStorageLayout.resolvedAvatarURL(in: root),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return decodeImage(data)
    }

    static func avatarURL(
        preset: DiceBearAvatarPreset,
        seed: String,
        pixelSize: Int = 256,
        format: String = "png"
    ) -> URL? {
        var components = URLComponents(string: "https://api.dicebear.com/\(apiVersion)/\(styleName)/\(format)")
        components?.queryItems = [
            URLQueryItem(name: "seed", value: seed),
            URLQueryItem(name: "size", value: String(pixelSize)),
            URLQueryItem(name: "hairVariant", value: preset.hairVariant),
            URLQueryItem(name: "facialHairProbability", value: String(preset.facialHairProbability)),
        ]
        return components?.url
    }

    static func previewImage(for preset: DiceBearAvatarPreset) -> UIImage? {
        guard let data = presetPNGData(preset) else { return nil }
        return decodeImage(data)
    }

    static func deleteCachedImage() {
        guard let root = UserDataPaths.activeUserRoot else { return }
        try? FileManager.default.removeItem(at: HikingStorageLayout.avatarURL(in: root))
        try? FileManager.default.removeItem(at: root.appendingPathComponent(HikingStorageLayout.Legacy.avatarFilename))
    }

    @discardableResult
    static func applyPresetImage(_ preset: DiceBearAvatarPreset) -> UIImage? {
        guard let data = presetPNGData(preset), let image = decodeImage(data) else {
            return nil
        }
        try? savePNGData(data)
        return image
    }

    /// SVG(초당 ~50)를 먼저 받고, 실패하면 원래 경로인 PNG 한 장만 받습니다.
    static func fetchAndCacheAvatar(preset: DiceBearAvatarPreset, seed: String) async -> UIImage? {
        if let image = await fetchSVG(preset: preset, seed: seed) {
            return image
        }
        if let image = await fetchRaster(preset: preset, seed: seed, pixelSize: 72, format: "png") {
            return image
        }
        return await fetchRaster(preset: preset, seed: seed, pixelSize: 256, format: "png")
    }

    private static func fetchRaster(
        preset: DiceBearAvatarPreset,
        seed: String,
        pixelSize: Int,
        format: String
    ) async -> UIImage? {
        guard let url = avatarURL(preset: preset, seed: seed, pixelSize: pixelSize, format: format) else {
            return nil
        }
        guard let data = await download(url) else { return nil }
        if looksLikeSVG(data) {
            return await rasterizeIfSVG(data)
        }
        return await MainActor.run {
            guard let image = decodeImage(data) else { return nil }
            try? savePNGData(image.pngData() ?? data)
            return image
        }
    }

    private static func fetchSVG(preset: DiceBearAvatarPreset, seed: String) async -> UIImage? {
        guard let url = avatarURL(preset: preset, seed: seed, pixelSize: 256, format: "svg") else {
            return nil
        }
        guard let data = await download(url) else { return nil }
        return await rasterizeIfSVG(data)
    }

    private static func rasterizeIfSVG(_ data: Data) async -> UIImage? {
        guard looksLikeSVG(data) else { return nil }
        let image = await DiceBearSVGRasterizer.image(fromSVG: data, dimension: 256)
        guard let image, let png = await MainActor.run(body: { image.pngData() }) else { return nil }
        try? savePNGData(png)
        return image
    }

    private static func download(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .returnCacheDataElseLoad

        for attempt in 1...2 {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    return nil
                }
                if http.statusCode == 429, attempt == 1 {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                guard (200...299).contains(http.statusCode), !data.isEmpty else {
                    return nil
                }
                return data
            } catch is CancellationError {
                return nil
            } catch {
                if attempt == 1 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    continue
                }
                return nil
            }
        }
        return nil
    }

    private static func looksLikeSVG(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(180), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return false
        }
        return prefix.contains("<svg") || prefix.hasPrefix("<?xml")
    }

    private static func decodeImage(_ data: Data) -> UIImage? {
        UIImage(data: data)
    }

    private static func presetPNGData(_ preset: DiceBearAvatarPreset) -> Data? {
        let bundles = [Bundle(for: DiceBearAvatarBundleToken.self), .main]
        let subdirectories = ["Resources/Avatars", "Avatars", nil]
        for bundle in bundles {
            for subdirectory in subdirectories {
                let url: URL?
                if let subdirectory {
                    url = bundle.url(forResource: preset.seed, withExtension: "png", subdirectory: subdirectory)
                } else {
                    url = bundle.url(forResource: preset.seed, withExtension: "png")
                }
                if let url, let data = try? Data(contentsOf: url), !data.isEmpty {
                    return data
                }
            }
        }
        return nil
    }

    private static func savePNGData(_ data: Data) throws {
        guard let url = cacheFileURL else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
    }
}

private final class DiceBearAvatarBundleToken {}

#endif
