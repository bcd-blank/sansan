//
//  HikingRecordDetailExport.swift
//  sansan
//

#if os(iOS)

import Combine
import Photos
import SwiftUI
import UIKit

/// 기록 상세 — 공유·GPX·사진 저장·경로 이미지 재생성.
@MainActor
final class HikingRecordExportCoordinator: ObservableObject {
    enum MenuAction {
        case regeneratingRouteImage
        case preparingShare
        case savingToPhotos
    }

    enum PendingDetailAction {
        case regenerateRouteImage
        case shareCard
        case shareGPX
        case saveToPhotos
        case followRoute
        case makeFlythrough
    }

    let recordID: UUID

    @Published var shareImage: UIImage?
    @Published var saveImage: UIImage?
    @Published var activeMenuAction: MenuAction?
    @Published var saveAlertMessage: String?
    @Published var showsDetailActions = false
    @Published var pendingDetailAction: PendingDetailAction?
    @Published var isExportCapturing = false
    @Published var progressOverlayMessage: String?
    @Published var isPrewarmingExportImage = false

    @Published var showsFlythrough = false
    @Published var flythroughPhase: FlythroughProgressPhase = .preparing(.analyzeRoute, progress: 0)
    @Published var flythroughVideoURL: URL?

    private let store = HikingRecordStore.shared
    private var backgroundWorkToken = UUID()
    private var flythroughTask: Task<Void, Never>?
    private let flythroughLiveActivity = FlythroughLiveActivityController()
    private var flythroughLifecycleObservers: [NSObjectProtocol] = []

    init(recordID: UUID) {
        self.recordID = recordID
    }

    func currentRecord(fallback: SavedHikingSession) -> SavedHikingSession {
        store.records.first(where: { $0.id == recordID }) ?? fallback
    }

    var isMenuBusy: Bool {
        isExportCapturing || activeMenuAction != nil || store.regeneratingRecordID == recordID || showsFlythrough
    }

    func canShareGPX(for record: SavedHikingSession) -> Bool {
        HikingGPXExporter.canExport(record: record)
    }

    func hasShareableRoute(for record: SavedHikingSession) -> Bool {
        record.session.points.count >= 2
    }

    func menuStatusMessage(for record: SavedHikingSession) -> String? {
        if progressOverlayMessage != nil || isExportCapturing {
            return nil
        }

        switch activeMenuAction {
        case .regeneratingRouteImage:
            return "경로 썸네일 이미지를 다시 그리는 중…"
        case .preparingShare:
            return "이미지 생성 중입니다."
        case .savingToPhotos:
            return "사진 앱에 저장하는 중…"
        case nil:
            if store.regeneratingRecordID == recordID {
                return "경로 썸네일 이미지를 다시 그리는 중…"
            }
            return nil
        }
    }

    func invalidateCachedImages() {
        shareImage = nil
        saveImage = nil
    }

    /// 상세 화면을 떠날 때 백그라운드 선생성·캡처를 중단합니다.
    func cancelBackgroundWork() {
        if showsFlythrough {
            cancelFlythrough()
            return
        }
        backgroundWorkToken = UUID()
        isPrewarmingExportImage = false
        isExportCapturing = false
        flythroughTask?.cancel()
        flythroughTask = nil
    }

    private func isBackgroundWorkCurrent(_ token: UUID) -> Bool {
        backgroundWorkToken == token
    }

    func queueDetailAction(_ action: PendingDetailAction) {
        pendingDetailAction = action
        showsDetailActions = false
    }

    func handleDetailActionsSheetDismissed(record: SavedHikingSession, onFollowRoute: () -> Void) {
        guard let action = pendingDetailAction else { return }
        pendingDetailAction = nil
        let current = currentRecord(fallback: record)

        switch action {
        case .regenerateRouteImage:
            beginMenuAction(.regeneratingRouteImage)
            Task { await regenerateRouteImage() }
        case .shareCard:
            progressOverlayMessage = "이미지 생성 중입니다."
            beginMenuAction(.preparingShare)
            Task { await presentShareSheet(record: current) }
        case .shareGPX:
            Task { await presentShareSheet(record: current, gpxOnly: true) }
        case .saveToPhotos:
            progressOverlayMessage = "이미지 생성 중입니다."
            beginMenuAction(.preparingShare)
            Task { await saveCardToPhotos(record: current) }
        case .followRoute:
            onFollowRoute()
        case .makeFlythrough:
            guard FlythroughCapabilities.isFeatureEnabled else { return }
            beginFlythrough(record: current)
        }
    }

    /// 3D 영상 — 옵션 시트가 닫힌 뒤 제작 화면을 애니메이션으로 표시합니다.
    func beginFlythrough(record: SavedHikingSession) {
        guard FlythroughCapabilities.isFeatureEnabled else { return }
        WorkoutManager.shared.cancelStartCountdown()
        flythroughTask?.cancel()
        cleanupFlythroughVideo()
        flythroughPhase = .preparing(.analyzeRoute, progress: 0)
        pendingDetailAction = nil

        withAnimation(.easeInOut(duration: 0.3)) {
            showsFlythrough = true
        }
        startFlythroughLiveActivity(record: record)

        flythroughTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            await runFlythroughGeneration(for: record)
        }
    }

    func canMakeFlythrough(for record: SavedHikingSession) -> Bool {
        FlythroughCapabilities.isFeatureEnabled && record.session.points.count >= 2
    }

    /// 일반설정에 저장된 옵션으로 3D 영상 렌더링을 시작합니다.
    func startFlythrough(record: SavedHikingSession) {
        beginFlythrough(record: record)
    }

    private func runFlythroughGeneration(for record: SavedHikingSession) async {
        let configuration = FlythroughVideoConfiguration.fromPreferences()
        let composer = HikingFlythroughComposer(configuration: configuration)
        do {
            let url = try await composer.makeVideo(from: record) { [weak self] phase in
                self?.flythroughPhase = phase
                self?.flythroughLiveActivity.update(phase: phase)
            }
            if Task.isCancelled { return }
            flythroughVideoURL = url
            flythroughPhase = .finished
            stopFlythroughLiveActivity()
        } catch is CancellationError {
            // 사용자 취소
            stopFlythroughLiveActivity()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "영상을 만들지 못했습니다."
            flythroughPhase = .failed(message)
            stopFlythroughLiveActivity()
        }
    }

    func cancelFlythrough() {
        flythroughTask?.cancel()
        flythroughTask = nil
        showsFlythrough = false
        flythroughPhase = .preparing(.analyzeRoute, progress: 0)
        cleanupFlythroughVideo()
        stopFlythroughLiveActivity()
    }

    /// 영상 제작 진행률을 다이나믹 아일랜드에 표시하고, 앱 이탈 시 일시정지 상태를 반영합니다.
    private func startFlythroughLiveActivity(record: SavedHikingSession) {
        flythroughLiveActivity.start(recordTitle: record.displayName ?? "등산 기록")
        guard flythroughLifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        flythroughLifecycleObservers = [
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.flythroughLiveActivity.setPaused(true)
                }
            },
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.flythroughLiveActivity.setPaused(false)
                }
            },
        ]
    }

    private func stopFlythroughLiveActivity() {
        flythroughLiveActivity.stop()
        for observer in flythroughLifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        flythroughLifecycleObservers = []
    }

    func cleanupFlythroughVideo() {
        if let url = flythroughVideoURL {
            try? FileManager.default.removeItem(at: url)
        }
        flythroughVideoURL = nil
    }

    func prewarmExportImageWhenMapReady(record: SavedHikingSession) async {
        let token = backgroundWorkToken
        guard hasShareableRoute(for: record) else { return }
        guard shareImage == nil, saveImage == nil else { return }
        guard !isExportCapturing, !isPrewarmingExportImage, !isMenuBusy else { return }

        for _ in 0..<30 {
            if !isBackgroundWorkCurrent(token) || Task.isCancelled { return }
            if LiveRouteMapSnapshotRegistry.shared.context(for: recordID) != nil {
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard isBackgroundWorkCurrent(token), !Task.isCancelled else { return }
        guard shareImage == nil, saveImage == nil else { return }
        isPrewarmingExportImage = true
        defer {
            if isBackgroundWorkCurrent(token) {
                isPrewarmingExportImage = false
            }
        }
        _ = await captureRecordCardImageForExport(
            showsProgress: false,
            workToken: token
        )
    }

    private func beginMenuAction(_ action: MenuAction) {
        activeMenuAction = action
    }

    private func endMenuAction(_ action: MenuAction) {
        if activeMenuAction == action {
            activeMenuAction = nil
        }
    }

    private func clearProgressOverlay() {
        progressOverlayMessage = nil
        endMenuAction(.preparingShare)
    }

    private func waitForCaptureReadyUI() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(80))
    }

    private func captureRecordCardImageForExport(
        forceRefresh: Bool = false,
        showsProgress: Bool = true,
        workToken: UUID? = nil
    ) async -> UIImage? {
        let token = workToken ?? backgroundWorkToken

        if !forceRefresh, let cached = shareImage ?? saveImage {
            return cached
        }

        if isPrewarmingExportImage, workToken == nil {
            for _ in 0..<60 {
                if !isPrewarmingExportImage { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if !forceRefresh, let cached = shareImage ?? saveImage {
                return cached
            }
        }

        guard isBackgroundWorkCurrent(token), !Task.isCancelled else { return nil }
        guard LiveRouteMapSnapshotRegistry.shared.context(for: recordID) != nil else { return nil }

        if showsProgress {
            progressOverlayMessage = "이미지 생성 중입니다."
            isExportCapturing = true
            await waitForCaptureReadyUI()
        }

        guard isBackgroundWorkCurrent(token), !Task.isCancelled else {
            if showsProgress { isExportCapturing = false }
            return nil
        }

        if forceRefresh {
            shareImage = nil
            saveImage = nil
            store.clearRouteImageCache(for: recordID)
        }

        let image = await store.shareImage(
            for: recordID,
            mapOptions: HikingShareExportPreferences.mapOptions,
            fullScreen: true
        )

        guard isBackgroundWorkCurrent(token), !Task.isCancelled else {
            if showsProgress { isExportCapturing = false }
            return nil
        }

        if showsProgress {
            isExportCapturing = false
        }
        shareImage = image
        saveImage = image
        return image
    }

    private func regenerateRouteImage() async {
        defer { endMenuAction(.regeneratingRouteImage) }
        await store.generateAndAttachSnapshot(for: recordID)
        invalidateCachedImages()
    }

    private func presentShareSheet(record: SavedHikingSession, gpxOnly: Bool = false) async {
        let shareTitle = record.listTitle

        if gpxOnly {
            guard canShareGPX(for: record) else {
                saveAlertMessage = "GPX를 만들 수 없습니다. GPS 포인트가 2개 이상 필요합니다."
                return
            }
            do {
                let gpxURL = try HikingGPXExporter.temporaryFileURL(for: record)
                guard GPXSharePresenter.present(fileURL: gpxURL, title: shareTitle) else {
                    saveAlertMessage = "공유 화면을 열지 못했습니다."
                    return
                }
            } catch {
                saveAlertMessage = "GPS 포인트가 2개 이상일 때 GPX를 만들 수 있습니다."
            }
            return
        }

        guard let cardImage = await captureRecordCardImageForExport(forceRefresh: true) else {
            clearProgressOverlay()
            saveAlertMessage = "공유할 항목을 만들지 못했습니다."
            return
        }

        clearProgressOverlay()

        let items: [Any] = [
            RecordCardShareActivityItem(image: cardImage, title: shareTitle)
        ]
        guard ActivitySharePresenter.present(items: items, mode: .recordCard) else {
            saveAlertMessage = "공유 화면을 열지 못했습니다."
            return
        }
    }

    private func saveCardToPhotos(record: SavedHikingSession) async {
        defer { clearProgressOverlay() }

        guard let imageToSave = await captureRecordCardImageForExport(forceRefresh: true) else {
            saveAlertMessage = "이미지를 만들지 못했습니다."
            return
        }

        progressOverlayMessage = "사진 앱에 저장하는 중…"
        endMenuAction(.preparingShare)
        beginMenuAction(.savingToPhotos)
        defer { endMenuAction(.savingToPhotos) }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveAlertMessage = "사진 앱 접근 권한이 필요합니다."
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(
                    from: imageToSave.preparedForPhotoLibraryExport()
                )
            }
            saveAlertMessage = "기록 카드가 사진 앱에 저장되었습니다."
        } catch {
            saveAlertMessage = "저장에 실패했습니다."
        }
    }
}

#endif
