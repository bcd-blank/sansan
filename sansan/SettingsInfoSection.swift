//
//  SettingsInfoSection.swift
//  sansan
//
//  일반설정 「정보」 — 버전 표시 + 업데이트 4상태.
//

#if os(iOS)

import SwiftUI

struct SettingsInfoSection: View {
    var status: AppUpdateStatus
    var versionLabel: String = AppUpdateChecker.localVersionLabel
    var marketingVersion: String = AppUpdateChecker.localMarketingVersion
    var buildVersion: String = AppUpdateChecker.localBuildVersion
    var onOpenStore: (URL) -> Void
    var onRetry: () -> Void

    var body: some View {
        Section {
            LabeledContent("버전", value: versionLabel)
                .accessibilityLabel("버전, \(marketingVersion) 빌드 \(buildVersion)")

            updateStatusRow
        } header: {
            Text("정보")
        } footer: {
            Text("업데이트는 App Store에서 설치됩니다. 기록 중에는 업데이트 알림을 띄우지 않습니다.")
        }
    }

    @ViewBuilder
    private var updateStatusRow: some View {
        switch status {
        case .checking:
            HStack {
                Text("업데이트")
                Spacer(minLength: 12)
                ProgressView()
                Text("확인 중…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("업데이트, 확인 중")

        case .upToDate:
            LabeledContent("업데이트", value: "최신 버전입니다")
                .accessibilityLabel("업데이트, 최신 버전입니다")

        case .available(let version, let url):
            Button {
                onOpenStore(url)
            } label: {
                HStack(spacing: 8) {
                    Text("업데이트")
                        .foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text("새 버전 \(version) 업데이트")
                        .foregroundStyle(Color.accentColor)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("업데이트, 새 버전 \(version) 업데이트")
            .accessibilityAddTraits(.isButton)

        case .failed:
            Button {
                onRetry()
            } label: {
                HStack {
                    Text("업데이트")
                        .foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    Text("확인할 수 없음 · 다시 확인")
                        .foregroundStyle(Color.accentColor)
                        .multilineTextAlignment(.trailing)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("업데이트, 확인할 수 없음, 다시 확인")
            .accessibilityAddTraits(.isButton)
        }
    }
}

#endif
