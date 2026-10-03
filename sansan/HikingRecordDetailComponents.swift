//
//  HikingRecordDetailComponents.swift
//  sansan
//

#if os(iOS)

import SwiftUI
import UIKit

struct HikingRecordDetailActionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isListPinned: Bool
    let isFavorite: Bool
    let isFollowDisabled: Bool
    let isRegenerateDisabled: Bool
    let isShareDisabled: Bool
    let isGPXShareDisabled: Bool
    let isSaveDisabled: Bool
    let onFollowRoute: () -> Void
    let onToggleListPinned: () -> Void
    let onToggleFavorite: () -> Void
    let onRegenerate: () -> Void
    let onShare: () -> Void
    let onShareGPX: () -> Void
    let onSaveToPhotos: () -> Void
    let isFlythroughDisabled: Bool
    let onMakeFlythrough: () -> Void
    var onAppear: (() -> Void)?

    private var showsFlythroughAction: Bool {
        FlythroughCapabilities.isFeatureEnabled
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("옵션")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PlainIconPressButtonStyle())
                    .accessibilityLabel("닫기")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            VStack(spacing: 8) {
                DetailActionRow(
                    title: "경로 따라가기",
                    subtitle: "기록 화면에 이 경로를 오렌지색으로 표시합니다.",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    isDisabled: isFollowDisabled,
                    action: onFollowRoute
                )
                DetailActionRow(
                    title: isListPinned ? "상단 고정 해제" : "상단 고정",
                    subtitle: "목록 맨 위에 표시합니다.",
                    systemImage: isListPinned ? "pin.slash" : "pin",
                    isDisabled: false,
                    action: onToggleListPinned
                )
                DetailActionRow(
                    title: isFavorite ? "즐겨찾기 해제" : "즐겨찾기",
                    subtitle: "즐겨찾기 그룹에 모아 둡니다.",
                    systemImage: isFavorite ? "star.slash" : "star",
                    isDisabled: false,
                    action: onToggleFavorite
                )
                DetailActionRow(
                    title: "경로 이미지 썸네일 다시 생성",
                    subtitle: "목록의 경로 썸네일 이미지를 다시 생성합니다.",
                    systemImage: "arrow.clockwise",
                    isDisabled: isRegenerateDisabled,
                    action: onRegenerate
                )
                if showsFlythroughAction {
                    DetailActionRow(
                        title: "3D 경로 영상 만들기",
                        subtitle: "경로를 따라 나는 3D 다시보기 영상을 만듭니다.",
                        systemImage: "video.badge.waveform",
                        isDisabled: isFlythroughDisabled,
                        action: onMakeFlythrough
                    )
                }
                DetailActionRow(
                    title: "기록 카드 공유",
                    subtitle: "지도와 요약이 담긴 이미지를 친구와 공유합니다.",
                    systemImage: "photo.on.rectangle.angled",
                    isDisabled: isShareDisabled,
                    action: onShare
                )
                DetailActionRow(
                    title: "GPX 파일 공유",
                    subtitle: "Strava, Garmin, 카카오맵 등 GPX 경로 앱으로 보냅니다.",
                    systemImage: "map.fill",
                    isDisabled: isGPXShareDisabled,
                    action: onShareGPX
                )
                DetailActionRow(
                    title: "사진에 저장",
                    subtitle: "기록 카드 이미지를 사진 앱에 저장합니다.",
                    systemImage: "photo.badge.arrow.down",
                    isDisabled: isSaveDisabled,
                    action: onSaveToPhotos
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            Spacer(minLength: 0)
        }
        .presentationDetents([.height(showsFlythroughAction ? 720 : 640)])
        .presentationDragIndicator(.visible)
        .onAppear { onAppear?() }
    }
}

struct DetailActionRow: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 24, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DetailActionPressButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}

struct DetailActionPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DetailActionPressButtonBody(configuration: configuration)
    }
}

struct DetailActionPressButtonBody: View {
    let configuration: ButtonStyle.Configuration

    var body: some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                guard isPressed else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
    }

    private var backgroundColor: Color {
        if configuration.isPressed {
            return Color.primary.opacity(0.1)
        }
        return Color(.secondarySystemGroupedBackground)
    }
}

struct PlainIconPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.45 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ToolbarIconPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                guard isPressed else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
    }
}

struct MenuActionStatusBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 기록 카드 이미지 생성·저장 중 — 화면 중앙 안내 (지도 캡처 영역과 분리).
struct RecordCardProgressOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.primary)

                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
            .padding(.horizontal, 40)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

#endif
