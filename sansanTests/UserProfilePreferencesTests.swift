//
//  UserProfilePreferencesTests.swift
//  sansanTests
//

import XCTest
@testable import sansan

final class UserProfilePreferencesTests: XCTestCase {
    func testMigratesUnsuffixedAvatarSourceToActiveUser() {
        let defaults = UserDefaults.standard
        let previousUserID = UserDataPaths.currentUserID
        let userID = "prefs-\(UUID().uuidString)"
        let unsuffixed = "sansan.userProfile.avatarSource"
        let suffixed = "\(unsuffixed).\(userID)"
        let previousUnsuffixed = defaults.string(forKey: unsuffixed)

        defaults.removeObject(forKey: suffixed)
        defaults.set(UserProfileAvatarSource.dicebear.rawValue, forKey: unsuffixed)
        UserDataPaths.setActiveUser(userID)
        defer {
            defaults.removeObject(forKey: suffixed)
            if let previousUnsuffixed {
                defaults.set(previousUnsuffixed, forKey: unsuffixed)
            } else {
                defaults.removeObject(forKey: unsuffixed)
            }
            if let previousUserID {
                UserDataPaths.setActiveUser(previousUserID)
            } else {
                UserDataPaths.clearActiveUser()
            }
            try? FileManager.default.removeItem(at: UserDataPaths.userRoot(userID: userID))
        }

        XCTAssertEqual(UserProfilePreferences.avatarSource, .dicebear)
        XCTAssertEqual(defaults.string(forKey: suffixed), UserProfileAvatarSource.dicebear.rawValue)
    }

    func testNextReloadSeedDoesNotPersistRoll() {
        let preset = DiceBearAvatarCatalog.defaultPreset
        let before = UserProfilePreferences.dicebearRollCount(for: preset.id)
        let seed = UserProfilePreferences.nextReloadSeed(for: preset)

        XCTAssertEqual(UserProfilePreferences.dicebearRollCount(for: preset.id), before)
        XCTAssertEqual(seed, UserProfilePreferences.seed(for: preset, roll: before + 1))
    }

    func testResetDicebearRollReturnsToBundledSeed() {
        let defaults = UserDefaults.standard
        let previousUserID = UserDataPaths.currentUserID
        let userID = "prefs-roll-\(UUID().uuidString)"
        UserDataPaths.setActiveUser(userID)
        defer {
            defaults.removeObject(forKey: "sansan.userProfile.dicebearRollCounts.\(userID)")
            if let previousUserID {
                UserDataPaths.setActiveUser(previousUserID)
            } else {
                UserDataPaths.clearActiveUser()
            }
            try? FileManager.default.removeItem(at: UserDataPaths.userRoot(userID: userID))
        }

        let preset = DiceBearAvatarCatalog.defaultPreset
        _ = UserProfilePreferences.incrementDicebearRoll(for: preset.id)
        XCTAssertNotEqual(UserProfilePreferences.effectiveSeed(for: preset), preset.seed)

        UserProfilePreferences.resetDicebearRoll(for: preset.id)
        XCTAssertEqual(UserProfilePreferences.dicebearRollCount(for: preset.id), 0)
        XCTAssertEqual(UserProfilePreferences.effectiveSeed(for: preset), preset.seed)
    }
}
