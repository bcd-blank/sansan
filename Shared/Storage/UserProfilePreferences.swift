//
//  UserProfilePreferences.swift
//  Shared
//

#if os(iOS)

import Foundation

enum UserProfileAvatarSource: String, Codable {
    case none
    case dicebear
    case custom
}

enum UserProfilePreferences {
    nonisolated private static let sourceKeyBase = "sansan.userProfile.avatarSource"
    nonisolated private static let seedKeyBase = "sansan.userProfile.dicebearSeed"
    nonisolated private static let presetKeyBase = "sansan.userProfile.dicebearPresetID"
    nonisolated private static let rollCountsKeyBase = "sansan.userProfile.dicebearRollCounts"

    nonisolated private static var sourceStorageKey: String {
        guard let userID = UserDataPaths.currentUserID else { return sourceKeyBase }
        return "\(sourceKeyBase).\(userID)"
    }

    nonisolated private static var seedStorageKey: String {
        guard let userID = UserDataPaths.currentUserID else { return seedKeyBase }
        return "\(seedKeyBase).\(userID)"
    }

    nonisolated private static var presetStorageKey: String {
        guard let userID = UserDataPaths.currentUserID else { return presetKeyBase }
        return "\(presetKeyBase).\(userID)"
    }

    nonisolated private static var rollCountsStorageKey: String {
        guard let userID = UserDataPaths.currentUserID else { return rollCountsKeyBase }
        return "\(rollCountsKeyBase).\(userID)"
    }

    nonisolated static var avatarSource: UserProfileAvatarSource {
        get {
            guard
                let raw = string(forPerUserKey: sourceStorageKey, unsuffixedKey: sourceKeyBase),
                let source = UserProfileAvatarSource(rawValue: raw)
            else {
                return .none
            }
            return source
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: sourceStorageKey)
        }
    }

    nonisolated static var dicebearPresetID: String? {
        get {
            string(forPerUserKey: presetStorageKey, unsuffixedKey: presetKeyBase)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: presetStorageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: presetStorageKey)
            }
        }
    }

    nonisolated static var selectedDiceBearPreset: DiceBearAvatarPreset {
        if let id = dicebearPresetID, let preset = DiceBearAvatarCatalog.preset(id: id) {
            return preset
        }
        return DiceBearAvatarCatalog.defaultPreset
    }

    nonisolated static func dicebearRollCount(for presetID: String) -> Int {
        dicebearRollCounts()[presetID] ?? 0
    }

    @discardableResult
    nonisolated static func incrementDicebearRoll(for presetID: String) -> Int {
        var counts = dicebearRollCounts()
        let next = (counts[presetID] ?? 0) + 1
        counts[presetID] = next
        saveDicebearRollCounts(counts)
        return next
    }

    nonisolated static func resetDicebearRoll(for presetID: String) {
        var counts = dicebearRollCounts()
        counts[presetID] = 0
        saveDicebearRollCounts(counts)
    }

    nonisolated static func seed(for preset: DiceBearAvatarPreset, roll: Int) -> String {
        guard roll > 0 else { return preset.seed }
        return "\(preset.seed)-r\(roll)"
    }

    nonisolated static func effectiveSeed(for preset: DiceBearAvatarPreset) -> String {
        seed(for: preset, roll: dicebearRollCount(for: preset.id))
    }

    nonisolated static func nextReloadSeed(for preset: DiceBearAvatarPreset) -> String {
        seed(for: preset, roll: dicebearRollCount(for: preset.id) + 1)
    }

    nonisolated static func clearDicebearRollCounts() {
        UserDefaults.standard.removeObject(forKey: rollCountsStorageKey)
    }

    /// 이전 버전(seed만 저장) 호환.
    nonisolated static var dicebearSeed: String {
        get { effectiveSeed(for: selectedDiceBearPreset) }
        set {
            _ = newValue
        }
    }

    /// 사용자 ID 접미사가 생기기 전에 저장된 값을 현재 키로 옮깁니다.
    nonisolated private static func string(forPerUserKey key: String, unsuffixedKey: String) -> String? {
        if let value = UserDefaults.standard.string(forKey: key) {
            return value
        }
        guard key != unsuffixedKey,
              let value = UserDefaults.standard.string(forKey: unsuffixedKey) else {
            return nil
        }
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    nonisolated private static func dicebearRollCounts() -> [String: Int] {
        if let counts = decodeRollCounts(forKey: rollCountsStorageKey) {
            return counts
        }
        guard rollCountsStorageKey != rollCountsKeyBase,
              let counts = decodeRollCounts(forKey: rollCountsKeyBase) else {
            return [:]
        }
        saveDicebearRollCounts(counts)
        return counts
    }

    nonisolated private static func decodeRollCounts(forKey key: String) -> [String: Int]? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return nil
        }
        return decoded
    }

    nonisolated private static func saveDicebearRollCounts(_ counts: [String: Int]) {
        guard let data = try? JSONEncoder().encode(counts) else { return }
        UserDefaults.standard.set(data, forKey: rollCountsStorageKey)
    }
}

#endif
