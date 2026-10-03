//
//  ProfileSettingsCard.swift
//  sansan
//

#if os(iOS)

import SwiftUI

struct ProfileSettingsCard: View {
    @ObservedObject var profilePhoto: UserProfilePhotoObserver
    var onPickPhoto: () -> Void
    var onDefaultAvatarFailed: () -> Void

    private let avatarDiameter: CGFloat = 52
    private let presetSize: CGFloat = 44
    private var routeTint: Color {
        Color(red: 0.12, green: 0.72, blue: 0.45)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            profileSummaryRow
            defaultAvatarSection
            secondaryActions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
    }

    private var profileSummaryRow: some View {
        HStack(alignment: .center, spacing: 12) {
            avatarView

            VStack(alignment: .leading, spacing: 6) {
                Text("프로필 사진")
                    .font(.subheadline.weight(.semibold))

                if let subtitle = statusSubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: onPickPhoto) {
                    Label("사진 선택", systemImage: "photo.on.rectangle.angled")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(profilePhoto.avatarSource == .custom ? routeTint : .accentColor)
            }

            Spacer(minLength: 0)
        }
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .strokeBorder(routeTint.opacity(0.18), lineWidth: 2)
                .frame(width: avatarDiameter + 6, height: avatarDiameter + 6)

            Group {
                if let image = profilePhoto.displayImage {
                    ProfileAvatarView(image: image, diameter: avatarDiameter)
                } else if profilePhoto.isLoadingDefaultAvatar {
                    ZStack {
                        Circle()
                            .fill(Color(.secondarySystemGroupedBackground))
                        ProgressView()
                            .controlSize(.small)
                    }
                    .frame(width: avatarDiameter, height: avatarDiameter)
                } else {
                    ZStack {
                        Circle()
                            .fill(Color(.secondarySystemGroupedBackground))
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: avatarDiameter, height: avatarDiameter)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(avatarAccessibilityLabel)
    }

    private var defaultAvatarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("기본 아바타")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DiceBearAvatarCatalog.presets) { preset in
                        DiceBearPresetPickerCell(
                            preset: preset,
                            isSelected: profilePhoto.avatarSource == .dicebear
                                && profilePhoto.selectedDiceBearPresetID == preset.id,
                            isLoading: profilePhoto.loadingDiceBearPresetID == preset.id,
                            previewImage: selectedPresetPreviewImage(for: preset)
                                ?? DiceBearAvatarStore.previewImage(for: preset),
                            tint: routeTint,
                            size: presetSize
                        ) {
                            Task {
                                if !(await profilePhoto.useDiceBearPreset(preset)) {
                                    onDefaultAvatarFailed()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var secondaryActions: some View {
        // Form 행 안에서 기본 스타일 버튼이 여러 개면 행 탭 한 번에 모두 발동하므로
        // 반드시 개별 탭 영역을 갖는 .borderless를 지정한다.
        HStack(spacing: 12) {
            if profilePhoto.avatarSource != .custom {
                Button {
                    Task {
                        if !(await profilePhoto.reloadDiceBearAvatar()) {
                            onDefaultAvatarFailed()
                        }
                    }
                } label: {
                    Label("새로 불러오기", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .disabled(profilePhoto.isLoadingDefaultAvatar)
            }

            if profilePhoto.avatarSource == .custom {
                Button("사진 삭제", role: .destructive) {
                    profilePhoto.removeCustomPhoto()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }

            if profilePhoto.avatarSource != .none {
                Button("아바타 제거") {
                    profilePhoto.clearAvatar()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if profilePhoto.isLoadingDefaultAvatar {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer(minLength: 0)
        }
    }

    private func selectedPresetPreviewImage(for preset: DiceBearAvatarPreset) -> UIImage? {
        guard profilePhoto.avatarSource == .dicebear,
              profilePhoto.selectedDiceBearPresetID == preset.id else {
            return nil
        }
        return profilePhoto.displayImage
    }

    private var statusSubtitle: String? {
        switch profilePhoto.avatarSource {
        case .none:
            return "사진 또는 아바타를 선택하세요."
        case .custom:
            return "업로드한 사진이 표시됩니다."
        case .dicebear:
            return nil
        }
    }

    private var avatarAccessibilityLabel: String {
        switch profilePhoto.avatarSource {
        case .none:
            return "프로필 사진 없음"
        case .custom:
            return "업로드한 프로필 사진"
        case .dicebear:
            return "선택한 기본 아바타"
        }
    }
}

private struct DiceBearPresetPickerCell: View {
    let preset: DiceBearAvatarPreset
    let isSelected: Bool
    let isLoading: Bool
    var previewImage: UIImage?
    let tint: Color
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    Circle()
                        .fill(Color(.secondarySystemGroupedBackground))
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    presetPlaceholder
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(isSelected ? tint : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 0.5)
            }
            .overlay(alignment: .bottomTrailing) {
                presentationBadge
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var presetPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color(.secondarySystemGroupedBackground))
            Image(systemName: "person.crop.circle")
                .font(.system(size: size * 0.38, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    private var presentationBadge: some View {
        Image(systemName: presentationBadgeSymbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(3)
            .background(Color.black.opacity(0.45), in: Circle())
            .offset(x: 1, y: 1)
    }

    private var presentationBadgeSymbol: String {
        switch preset.presentation {
        case .male:
            return "m.circle.fill"
        case .female:
            return "f.circle.fill"
        case .neutral:
            return "person.crop.circle.fill"
        }
    }
}

#endif
