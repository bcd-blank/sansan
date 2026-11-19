//
//  ProfileAvatarView.swift
//  sansan
//

#if os(iOS)

import SwiftUI

struct ProfileAvatarView: View {
    let image: UIImage
    var diameter: CGFloat = 36

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .accessibilityLabel("프로필 아바타")
    }
}

/// 프로필이 설정되지 않았을 때 표시하는 기본 이미지.
struct ProfileAvatarPlaceholderView: View {
    var diameter: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.secondarySystemGroupedBackground))
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .padding(diameter * 0.08)
                .foregroundStyle(Color.secondary.opacity(0.55))
        }
        .frame(width: diameter, height: diameter)
        .overlay {
            Circle()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityLabel("프로필 사진 없음")
    }
}

#endif
