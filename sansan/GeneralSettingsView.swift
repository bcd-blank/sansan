//
//  GeneralSettingsView.swift
//  sansan
//

#if os(iOS)

import SwiftUI

struct GeneralSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var iCloudSync = ICloudRecordSync.shared
    @ObservedObject private var snapshotPreferences = HikingSnapshotPreferencesObserver.shared
    @ObservedObject private var shareExportPreferences = HikingShareExportPreferencesObserver.shared
    @ObservedObject private var mapDisplayPreferences = HikingMapDisplayPreferencesObserver.shared
    @ObservedObject private var heartRatePreferences = HeartRatePreferencesObserver.shared
    @ObservedObject private var flythroughPreferences = HikingFlythroughPreferencesObserver.shared
    @ObservedObject private var themePreferences = AppThemePreferencesObserver.shared
    @ObservedObject private var bodyMetrics = BodyMetricsPreferencesObserver.shared
    @ObservedObject private var recordStore = HikingRecordStore.shared
    @ObservedObject private var profilePhoto = UserProfilePhotoObserver.shared
    @State private var shareMapOptions = HikingShareExportPreferences.mapOptions
    @State private var showsSummitMarkers = HikingMapDisplayPreferences.showsSummitMarkers
    @State private var isHeartRateFeatureEnabled = HeartRatePreferences.isFeatureEnabled
    @State private var flythroughOrientation = HikingFlythroughPreferences.orientation
    @State private var flythroughMapStyle = HikingFlythroughPreferences.mapStyle
    @State private var flythroughShowsPhotoMarkers = HikingFlythroughPreferences.showsPhotoMarkers
    @State private var flythroughShowsDistanceMarkers = HikingFlythroughPreferences.showsDistanceMarkers
    @State private var flythroughQuality = HikingFlythroughPreferences.quality
    @State private var flythroughTitleSource = HikingFlythroughPreferences.titleSource
    @State private var appTheme = AppThemePreferences.theme
    @State private var showsBodyMassEditor = false
    @State private var bodyMassDraft = ""
    @State private var showsPathImageInfo = false
    @State private var showsSignOutConfirmation = false
    @State private var showsProfilePhotoPicker = false
    @State private var profilePhotoSaveFailed = false
    @State private var defaultAvatarLoadFailed = false
    @State private var showHeartRatePermissionPrimer = false
    @State private var pendingHeartRateEnable = false

    var body: some View {
        formWithPresentations
            .onAppear {
                syncPreferencesFromStorage()
            }
            .onChange(of: shareMapOptions) { _, newOptions in
                shareExportPreferences.setMapOptions(newOptions)
            }
            .onChange(of: showsSummitMarkers) { _, isOn in
                mapDisplayPreferences.setShowsSummitMarkers(isOn)
            }
            .onChange(of: flythroughOrientation) { _, value in
                flythroughPreferences.setOrientation(value)
            }
            .onChange(of: flythroughMapStyle) { _, value in
                flythroughPreferences.setMapStyle(value)
            }
            .onChange(of: flythroughShowsPhotoMarkers) { _, value in
                flythroughPreferences.setShowsPhotoMarkers(value)
            }
            .onChange(of: flythroughShowsDistanceMarkers) { _, value in
                flythroughPreferences.setShowsDistanceMarkers(value)
            }
            .onChange(of: flythroughQuality) { _, value in
                flythroughPreferences.setQuality(value)
            }
            .onChange(of: flythroughTitleSource) { _, value in
                flythroughPreferences.setTitleSource(value)
            }
            .onChange(of: appTheme) { _, value in
                themePreferences.setTheme(value)
            }
            .onChange(of: isHeartRateFeatureEnabled) { oldValue, isOn in
                if isOn, !oldValue, !pendingHeartRateEnable {
                    isHeartRateFeatureEnabled = false
                    pendingHeartRateEnable = true
                    showHeartRatePermissionPrimer = true
                    return
                }
                guard !pendingHeartRateEnable else { return }
                Task {
                    await WorkoutManager.shared.setHeartRateFeatureEnabled(isOn)
                }
            }
    }

    private var settingsForm: some View {
        Form {
            Section {
                ProfileSettingsCard(
                    profilePhoto: profilePhoto,
                    onPickPhoto: { showsProfilePhotoPicker = true },
                    onDefaultAvatarFailed: { defaultAvatarLoadFailed = true }
                )
            } header: {
                Text("프로필")
            } footer: {
                Text("메인 화면·기록 상세·저장 이미지의 타이틀 카드에 원형으로 표시됩니다.")
            }

            if AuthCapabilities.isSignInEnabled, let user = auth.currentUser {
                Section("계정") {
                    LabeledContent("로그인 방식", value: user.providerLabel)
                    LabeledContent("이름", value: user.shortDisplayName)
                    Button("로그아웃", role: .destructive) {
                        showsSignOutConfirmation = true
                    }
                }
            }

            if StorageCapabilities.isICloudSyncEnabled {
            Section {
                if iCloudSync.isAvailable {
                    LabeledContent("상태", value: iCloudSync.statusLabel)
                    if let lastSyncDate = iCloudSync.lastSyncDate {
                        LabeledContent("마지막 동기화") {
                            Text(lastSyncDate.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    Button("지금 iCloud 동기화") {
                        Task {
                            await iCloudRecordSyncNow()
                        }
                    }
                    .disabled(iCloudSync.isSyncing)
                } else {
                    Text("iCloud에 로그인되어 있지 않거나 사용할 수 없습니다. 설정 → Apple ID → iCloud에서 iCloud Drive를 켜 주세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("iCloud 백업")
            } footer: {
                Text("등산 기록·사진이 iCloud Drive의 sansan 폴더에 저장됩니다. 파일 앱에서 확인할 수 있고, 앱을 삭제 후 재설치해도 같은 Apple ID로 복구할 수 있습니다.")
            }
            }

            Section {
                Picker("테마", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } header: {
                Text("화면")
            } footer: {
                Text("앱 전체의 밝기 테마를 선택합니다. 시스템 설정은 기기 설정을 따릅니다.")
            }

            Section {
                Toggle("정상 표시", isOn: $showsSummitMarkers)
            } header: {
                Text("지도")
            } footer: {
                Text("기록 중·기록 상세 지도에 경로 근처 산 정상 이름을 표시합니다.")
            }

            Section {
                Toggle("심박수 측정", isOn: $isHeartRateFeatureEnabled)
            } header: {
                Text("건강")
            } footer: {
                Text("켜면 메인 화면에 심박수 카드가 표시됩니다. Apple Watch 착용 시 건강 앱 데이터를 기록합니다.")
            }

            Section {
                Button {
                    bodyMassDraft = bodyMetrics.bodyMassKilograms.map { String(format: "%g", $0) } ?? ""
                    showsBodyMassEditor = true
                } label: {
                    HStack {
                        Text("체중")
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        Text(bodyMassDisplayText)
                            .foregroundStyle(bodyMetrics.bodyMassKilograms == nil ? .secondary : .primary)
                            .monospacedDigit()
                        Text("kg")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("신체 정보")
            } footer: {
                Text("아이폰 단독 기록의 칼로리 추정에 사용됩니다. Apple Watch로 기록하면 건강 앱 실측 칼로리를 사용합니다.")
            }

            Section {
                Toggle("구간 표시", isOn: $shareMapOptions.showsDistanceMarkers)
                Toggle("사진 위치 표시", isOn: $shareMapOptions.showsPhotoMarkers)
                Toggle("고정 사진 썸네일", isOn: $shareMapOptions.showsPinnedThumbnails)
            } header: {
                Text("저장 · 공유 지도")
            } footer: {
                Text("공유·저장 이미지에 표시할 항목을 선택합니다. 구간 표시는 1km 단위 거리 라벨입니다.")
            }

            if FlythroughCapabilities.isFeatureEnabled {
                flythroughSettingsSection
            }

            if HikingSnapshotStyle.isUserStyleSelectionEnabled {
                Section {
                    ForEach(HikingSnapshotStyle.allCases, id: \.self) { style in
                        Button {
                            guard snapshotPreferences.setStyle(style) else { return }
                            Task {
                                await recordStore.regenerateAllSnapshots()
                            }
                        } label: {
                            HStack {
                                Text(style.displayName)
                                Spacer()
                                if snapshotPreferences.style == style {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .disabled(recordStore.isGeneratingSnapshot)
                    }
                } header: {
                    pathImageSectionHeader
                } footer: {
                    if recordStore.isGeneratingSnapshot {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("경로 이미지를 다시 그리는 중…")
                        }
                    } else {
                        Text("로고 표시는 바로 바뀌고, 저장된 경로 PNG도 자동으로 다시 그려집니다.")
                    }
                }
            }
        }
    }

    private var formWithPresentations: some View {
        settingsForm
        .navigationTitle("일반설정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("완료") { dismiss() }
            }
        }
        .alert("경로 이미지", isPresented: $showsPathImageInfo) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(HikingSnapshotStyle.settingsHelpMessage)
        }
        .confirmationDialog(
            "로그아웃하시겠습니까?",
            isPresented: $showsSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("로그아웃", role: .destructive) {
                auth.signOut()
                dismiss()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 기기에 저장된 등산 기록은 계정에 남아 있으며, 다시 로그인하면 불러올 수 있습니다.")
        }
        .sheet(isPresented: $showsProfilePhotoPicker) {
            ProfilePhotoLibraryPicker { image in
                if !profilePhoto.save(image) {
                    profilePhotoSaveFailed = true
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsBodyMassEditor) {
            BodyMassEditSheet(
                draft: $bodyMassDraft,
                onSave: commitBodyMassDraft,
                onCancel: { showsBodyMassEditor = false }
            )
        }
        .alert("프로필 사진 저장 실패", isPresented: $profilePhotoSaveFailed) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("사진을 저장하지 못했습니다. 다시 시도해 주세요.")
        }
        .alert("기본 아바타 불러오기 실패", isPresented: $defaultAvatarLoadFailed) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("DiceBear 아바타를 불러오지 못했습니다. 네트워크 연결을 확인한 뒤 다시 시도해 주세요.")
        }
        .alert(PermissionPrimerCopy.heartRateTitle, isPresented: $showHeartRatePermissionPrimer) {
            Button(PermissionPrimerCopy.allowButtonTitle) {
                pendingHeartRateEnable = false
                isHeartRateFeatureEnabled = true
                Task {
                    await WorkoutManager.shared.setHeartRateFeatureEnabled(true)
                }
            }
            Button("취소", role: .cancel) {
                pendingHeartRateEnable = false
                isHeartRateFeatureEnabled = false
            }
        } message: {
            Text(PermissionPrimerCopy.heartRateMessage)
        }
    }

    private var flythroughSettingsSection: some View {
        Section {
            Picker("화면 방향", selection: $flythroughOrientation) {
                ForEach(FlythroughOrientation.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            Picker("지도", selection: $flythroughMapStyle) {
                ForEach(FlythroughMapStyle.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            Picker("화질", selection: $flythroughQuality) {
                ForEach(FlythroughQuality.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            Text(flythroughQuality.settingsHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("영상 타이틀", selection: $flythroughTitleSource) {
                ForEach(FlythroughTitleSource.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            Toggle("사진 라벨", isOn: $flythroughShowsPhotoMarkers)
            Toggle("거리 라벨", isOn: $flythroughShowsDistanceMarkers)
        } header: {
            Text("3D 경로 영상")
        } footer: {
            Text("기록 상세에서 만드는 3D 다시보기 영상의 기본 설정입니다. 영상 타이틀은 주변 산 지명을 자동 검색하거나 기록의 타이틀을 그대로 사용합니다.")
        }
    }

    private func syncPreferencesFromStorage() {
        profilePhoto.syncFromStorage()
        snapshotPreferences.syncFromStorage()
        shareExportPreferences.syncFromStorage()
        mapDisplayPreferences.syncFromStorage()
        heartRatePreferences.syncFromStorage()
        flythroughPreferences.syncFromStorage()
        themePreferences.syncFromStorage()
        bodyMetrics.syncFromStorage()
        shareMapOptions = shareExportPreferences.mapOptions
        showsSummitMarkers = mapDisplayPreferences.showsSummitMarkers
        isHeartRateFeatureEnabled = heartRatePreferences.isFeatureEnabled
        flythroughOrientation = flythroughPreferences.orientation
        flythroughMapStyle = flythroughPreferences.mapStyle
        flythroughShowsPhotoMarkers = flythroughPreferences.showsPhotoMarkers
        flythroughShowsDistanceMarkers = flythroughPreferences.showsDistanceMarkers
        flythroughQuality = flythroughPreferences.quality
        flythroughTitleSource = flythroughPreferences.titleSource
        appTheme = themePreferences.theme
        if StorageCapabilities.isICloudSyncEnabled {
            Task { await iCloudSync.refreshAvailability() }
        }
    }

    private func iCloudRecordSyncNow() async {
        await iCloudSync.pullAndMerge()
        HikingRecordStore.shared.reloadForCurrentUser()
    }

    private var bodyMassDisplayText: String {
        if let kilograms = bodyMetrics.bodyMassKilograms {
            return String(format: "%g", kilograms)
        }
        return "\(Int(BodyMetricsPreferences.defaultBodyMassKilograms))"
    }

    private func commitBodyMassDraft() {
        let normalized = bodyMassDraft.replacingOccurrences(of: ",", with: ".")
        bodyMetrics.setBodyMass(Double(normalized))
        showsBodyMassEditor = false
    }

    private var pathImageSectionHeader: some View {
        HStack(spacing: 6) {
            Text("경로 이미지")
            Button {
                showsPathImageInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("경로 이미지 설정 안내")
        }
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
    }
}

#endif
