//
//  DiceBearAvatarStoreTests.swift
//  sansanTests
//

import XCTest
@testable import sansan

final class DiceBearAvatarStoreTests: XCTestCase {
    func testBundlesPreviewForEveryPreset() {
        for preset in DiceBearAvatarCatalog.presets {
            XCTAssertNotNil(DiceBearAvatarStore.previewImage(for: preset), preset.id)
        }
    }

    func testReloadURLKeepsPresetTraitsAndChangesSeed() {
        let preset = DiceBearAvatarCatalog.defaultPreset
        let first = DiceBearAvatarStore.avatarURL(preset: preset, seed: preset.seed)
        let reloaded = DiceBearAvatarStore.avatarURL(
            preset: preset,
            seed: UserProfilePreferences.seed(for: preset, roll: 1)
        )
        let svg = DiceBearAvatarStore.avatarURL(
            preset: preset,
            seed: UserProfilePreferences.seed(for: preset, roll: 1),
            format: "svg"
        )

        XCTAssertNotNil(first)
        XCTAssertNotNil(reloaded)
        XCTAssertNotEqual(first, reloaded)
        XCTAssertTrue(reloaded?.absoluteString.contains("hairVariant=\(preset.hairVariant)") == true)
        XCTAssertTrue(
            reloaded?.absoluteString.contains("facialHairProbability=\(preset.facialHairProbability)") == true
        )
        XCTAssertTrue(reloaded?.absoluteString.contains("-r1") == true)
        XCTAssertTrue(svg?.absoluteString.contains("/dylan/svg") == true)
    }

    func testFetchesReloadCombinationFromDiceBearAPI() async {
        let previous = UserDataPaths.currentUserID
        let userID = "avatar-fetch-\(UUID().uuidString)"
        UserDataPaths.setActiveUser(userID)
        defer {
            try? FileManager.default.removeItem(at: UserDataPaths.userRoot(userID: userID))
            if let previous {
                UserDataPaths.setActiveUser(previous)
            } else {
                UserDataPaths.clearActiveUser()
            }
        }

        let preset = DiceBearAvatarCatalog.presets[3]
        let image = await DiceBearAvatarStore.fetchAndCacheAvatar(
            preset: preset,
            seed: UserProfilePreferences.seed(for: preset, roll: 1)
        )
        XCTAssertNotNil(image)
        XCTAssertNotNil(DiceBearAvatarStore.loadCachedImage())
    }
}
