//
//  AppShellView.swift
//  sansan
//

#if os(iOS)

import SwiftUI

/// 시스템 런치 화면(Info.plist) 이후 메인(또는 로그인)으로 전환.
struct AppShellView: View {
    @ObservedObject private var auth = AuthManager.shared
    @Environment(\.scenePhase) private var scenePhase

    private enum Phase: Equatable {
        case booting
        case login
        case main
    }

    @State private var phase: Phase = .booting

    var body: some View {
        Group {
            switch phase {
            case .booting:
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                    .overlay {
                        ProgressView()
                            .controlSize(.regular)
                    }
            case .login:
                LoginView()
            case .main:
                iPhoneRootView()
            }
        }
        .task(priority: .userInitiated) {
            await performInitialBoot()
        }
        .onChange(of: auth.isAuthenticated) { _, isAuthenticated in
            guard AuthCapabilities.isSignInEnabled, phase != .booting else { return }
            if isAuthenticated {
                Task {
                    await configureDataLayer(awaitICloudPull: false)
                    AppThemePreferencesObserver.shared.syncFromStorage()
                    schedulePostMainWarmup()
                }
                phase = .main
            } else {
                phase = .login
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // WorkoutManager를 ObservedObject로 두지 않음 — 워치 동기화마다 셸이 재그려져
            // 메인 UI가 빈 화면처럼 보이는 회귀를 막습니다.
            WorkoutManager.shared.refreshLocationTrackingIfNeeded()
            WorkoutManager.shared.syncPendingWatchSessions()
        }
        .overlay {
            RecordPersistFailureAlertHost()
        }
    }

    @MainActor
    private func performInitialBoot() async {
        if AuthCapabilities.isSignInEnabled {
            AuthManager.shared.supplementalAuth = GoogleSignInCoordinator.shared
            await AuthManager.shared.restoreSession()
            AppThemePreferencesObserver.shared.syncFromStorage()
            if auth.isAuthenticated {
                await configureDataLayer(awaitICloudPull: false)
                phase = .main
                schedulePostMainWarmup()
            } else {
                phase = .login
            }
        } else {
            UserDataPaths.activateLocalUser()
            AppThemePreferencesObserver.shared.syncFromStorage()
            // iCloud pull을 기다리지 않고 메인 UI를 먼저 올립니다.
            // 워치 앱이 켜져 있으면 WC MainActor 작업과 iCloud 대기가 겹쳐 흰 화면이 길어질 수 있습니다.
            await configureDataLayer(awaitICloudPull: false)
            phase = .main
            schedulePostMainWarmup()
        }
    }

    @MainActor
    private func configureDataLayer(awaitICloudPull: Bool) async {
        _ = HikingRecordStore.shared
        HikingRecordStore.shareImageRenderer = { record, routeImage, fullScreen in
            HikingRecordShareComposer.render(
                record: record,
                routeImage: routeImage,
                format: fullScreen ? .fullScreen : .contentSized
            )
        }
        HikingRecordStore.detailShareMapCanvasProvider = {
            (
                size: HikingRecordShareDeviceMetrics.detailMapCanvasSize,
                pixelScale: HikingRecordShareDeviceMetrics.nativeScale
            )
        }
        HikingRouteSnapshotGenerator.allowsLiveDetailCapture = { recordID in
            LiveRouteMapSnapshotRegistry.shared.context(for: recordID) != nil
        }
        HikingRouteSnapshotGenerator.captureRouteMapBase = RouteMapSnapshotCapture.captureForGenerator
        if awaitICloudPull, StorageCapabilities.isICloudSyncEnabled {
            await ICloudRecordSync.shared.pullAndMerge()
        }
    }

    /// 첫 메인 프레임(지도·버튼)이 살아난 뒤에 무거운 I/O를 이어갑니다.
    private func schedulePostMainWarmup() {
        Task { @MainActor in
            await Task.yield()
            await HikingRecordStore.shared.reloadForCurrentUserOffMain()
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            await pullICloudInBackgroundIfNeeded()
        }
        Task {
            try? await Task.sleep(for: .seconds(5))
            MountainSummitCatalog.preload()
        }
    }

    @MainActor
    private func pullICloudInBackgroundIfNeeded() async {
        guard StorageCapabilities.isICloudSyncEnabled else { return }
        if !HikingRecordStore.shared.hasCompletedInitialLoad {
            await HikingRecordStore.shared.reloadForCurrentUserOffMain()
        }
        await ICloudRecordSync.shared.pullAndMerge()
        await HikingRecordStore.shared.reloadForCurrentUserOffMain()
    }
}

/// 기록 저장소 갱신으로 메인 셸 전체가 다시 그려지지 않도록 알림만 분리합니다.
private struct RecordPersistFailureAlertHost: View {
    @ObservedObject private var recordStore = HikingRecordStore.shared

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .alert("기록 저장 실패", isPresented: showsPersistFailureAlert) {
                Button("다시 시도") {
                    recordStore.retryPersist()
                }
                Button("확인", role: .cancel) {
                    recordStore.dismissPersistFailure()
                }
            } message: {
                Text(recordStore.persistFailure?.message ?? "")
            }
    }

    private var showsPersistFailureAlert: Binding<Bool> {
        Binding(
            get: { recordStore.persistFailure != nil },
            set: { isPresented in
                if !isPresented {
                    recordStore.dismissPersistFailure()
                }
            }
        )
    }
}

#endif
