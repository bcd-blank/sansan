//
//  DiceBearAvatarCatalog.swift
//  Shared
//
//  DiceBear Dylan — 기본 아바타 프리셋.
//  https://www.dicebear.com/styles/dylan/
//

#if os(iOS)

import Foundation

enum DiceBearAvatarPresentation: String, Codable, Sendable {
    case male
    case female
    case neutral
}

struct DiceBearAvatarPreset: Identifiable, Equatable, Sendable {
    let id: String
    let seed: String
    let presentation: DiceBearAvatarPresentation
    let hairVariant: String
    let facialHairProbability: Int

    var accessibilityLabel: String {
        switch presentation {
        case .male:
            return "남성 기본 아바타"
        case .female:
            return "여성 기본 아바타"
        case .neutral:
            return "중성 기본 아바타"
        }
    }
}

enum DiceBearAvatarCatalog {
    nonisolated static let presets: [DiceBearAvatarPreset] = [
        DiceBearAvatarPreset(
            id: "dylan-male-1",
            seed: "sansan-dylan-male-1",
            presentation: .male,
            hairVariant: "plain",
            facialHairProbability: 100
        ),
        DiceBearAvatarPreset(
            id: "dylan-male-2",
            seed: "sansan-dylan-male-2",
            presentation: .male,
            hairVariant: "flatTop",
            facialHairProbability: 80
        ),
        DiceBearAvatarPreset(
            id: "dylan-female-1",
            seed: "sansan-dylan-female-1",
            presentation: .female,
            hairVariant: "longCurls",
            facialHairProbability: 0
        ),
        DiceBearAvatarPreset(
            id: "dylan-female-2",
            seed: "sansan-dylan-female-2",
            presentation: .female,
            hairVariant: "roundBob",
            facialHairProbability: 0
        ),
        DiceBearAvatarPreset(
            id: "dylan-neutral-1",
            seed: "sansan-dylan-neutral-1",
            presentation: .neutral,
            hairVariant: "parting",
            facialHairProbability: 15
        ),
        DiceBearAvatarPreset(
            id: "dylan-neutral-2",
            seed: "sansan-dylan-neutral-2",
            presentation: .neutral,
            hairVariant: "wavy",
            facialHairProbability: 10
        ),
    ]

    nonisolated static var defaultPreset: DiceBearAvatarPreset {
        presets[0]
    }

    nonisolated static func preset(id: String) -> DiceBearAvatarPreset? {
        presets.first { $0.id == id }
    }
}

#endif
