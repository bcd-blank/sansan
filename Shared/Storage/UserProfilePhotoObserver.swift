//
//  UserProfilePhotoObserver.swift
//  Shared
//

#if os(iOS)

import Combine
import UIKit

@MainActor
final class UserProfilePhotoObserver: ObservableObject {
    static let shared = UserProfilePhotoObserver()

    @Published private(set) var avatarSource: UserProfileAvatarSource = .none
    @Published private(set) var displayImage: UIImage?
    @Published private(set) var selectedDiceBearPresetID: String?
    @Published private(set) var loadingDiceBearPresetID: String?

    /// 기존 호출부 호환.
    var image: UIImage? { displayImage }
    var isLoadingDefaultAvatar: Bool { loadingDiceBearPresetID != nil }

    private init() {
        avatarSource = UserProfilePreferences.avatarSource
        selectedDiceBearPresetID = UserProfilePreferences.dicebearPresetID
        displayImage = resolveSynchronousImage(for: avatarSource)
    }

    func syncFromStorage() {
        Task { await refreshDisplayImage() }
    }

    func clearForSignOut() {
        avatarSource = .none
        displayImage = nil
        selectedDiceBearPresetID = nil
        loadingDiceBearPresetID = nil
    }

    func refreshDisplayImage() async {
        let source = UserProfilePreferences.avatarSource
        avatarSource = source
        selectedDiceBearPresetID = UserProfilePreferences.dicebearPresetID

        switch source {
        case .none:
            displayImage = nil
        case .custom:
            displayImage = UserProfilePhotoStore.loadImage()
            if displayImage == nil {
                UserProfilePreferences.avatarSource = .none
                avatarSource = .none
            }
        case .dicebear:
            if UserProfilePreferences.dicebearPresetID == nil {
                UserProfilePreferences.dicebearPresetID = DiceBearAvatarCatalog.defaultPreset.id
                selectedDiceBearPresetID = UserProfilePreferences.dicebearPresetID
            }
            if let cached = DiceBearAvatarStore.loadCachedImage() {
                displayImage = cached
            } else {
                displayImage = DiceBearAvatarStore.applyPresetImage(
                    UserProfilePreferences.selectedDiceBearPreset
                )
            }
        }
    }

    @discardableResult
    func useDiceBearPreset(_ preset: DiceBearAvatarPreset) async -> Bool {
        UserProfilePreferences.resetDicebearRoll(for: preset.id)
        UserProfilePreferences.dicebearPresetID = preset.id
        UserProfilePreferences.avatarSource = .dicebear
        avatarSource = .dicebear
        selectedDiceBearPresetID = preset.id

        guard let image = DiceBearAvatarStore.applyPresetImage(preset) else {
            return false
        }
        displayImage = image
        return true
    }

    @discardableResult
    func save(_ newImage: UIImage) -> Bool {
        do {
            _ = try UserProfilePhotoStore.save(newImage)
            UserProfilePreferences.avatarSource = .custom
            avatarSource = .custom
            displayImage = UserProfilePhotoStore.loadImage()
            return true
        } catch {
            return false
        }
    }

    func removeCustomPhoto() {
        UserProfilePhotoStore.deletePhoto()
        if UserProfilePreferences.avatarSource == .custom {
            UserProfilePreferences.avatarSource = .none
            avatarSource = .none
            displayImage = nil
        }
    }

    func clearAvatar() {
        UserProfilePhotoStore.deletePhoto()
        DiceBearAvatarStore.deleteCachedImage()
        UserProfilePreferences.avatarSource = .none
        // 마지막 프리셋·회차는 지우지 않는다.
        // 제거 후 「새로 불러오기」가 같은 특성의 다음 조합을 이어서 받도록.
        avatarSource = .none
        selectedDiceBearPresetID = nil
        displayImage = nil
    }

    /// 「새로 불러오기」— 현재(또는 마지막) 프리셋의 머리·수염 특성을 유지한 채
    /// 새 seed로 DiceBear에서 새 조합을 받아 적용한다.
    /// 아바타를 제거한 직후에 눌러도 새 아바타를 받아온다.
    @discardableResult
    func reloadDiceBearAvatar() async -> Bool {
        let preset = UserProfilePreferences.selectedDiceBearPreset
        let nextSeed = UserProfilePreferences.nextReloadSeed(for: preset)
        let previousSource = avatarSource
        let previousImage = displayImage

        loadingDiceBearPresetID = preset.id
        defer {
            if loadingDiceBearPresetID == preset.id {
                loadingDiceBearPresetID = nil
            }
        }

        let image = await DiceBearAvatarStore.fetchAndCacheAvatar(preset: preset, seed: nextSeed)

        if let image {
            UserProfilePreferences.incrementDicebearRoll(for: preset.id)
            UserProfilePreferences.dicebearPresetID = preset.id
            UserProfilePreferences.avatarSource = .dicebear
            avatarSource = .dicebear
            selectedDiceBearPresetID = preset.id
            displayImage = image
            return true
        }

        avatarSource = previousSource
        displayImage = previousImage
        return false
    }

    private func resolveSynchronousImage(for source: UserProfileAvatarSource) -> UIImage? {
        switch source {
        case .none:
            return nil
        case .custom:
            return UserProfilePhotoStore.loadImage()
        case .dicebear:
            return DiceBearAvatarStore.loadCachedImage()
                ?? DiceBearAvatarStore.applyPresetImage(UserProfilePreferences.selectedDiceBearPreset)
        }
    }
}

#endif
