//
//  MidHikeShareCoordinator.swift
//  sansan
//
//  산행 기록 중(일시정지 포함) 지금까지의 기록 카드 저장·공유.
//  완료 후 `HikingRecordExportCoordinator` 파이프라인을 재사용하되,
//  미저장 세션·LiveRouteMapSnapshotRegistry 전제를 우회합니다.
//

#if os(iOS)

import Combine
import Photos
import SwiftUI
import UIKit

/// 기록 중 세션 → 임시 `SavedHikingSession` (원본 live session은 변경하지 않음).
enum MidHikeShareSnapshot {
    static func makeRecord(
        from session: HikingSessionData,
        capturedAt: Date = Date()
    ) -> SavedHikingSession {
        // `SavedHikingSession.init`이 session 복사본의 state를 `.idle`로 아카이브함.
        SavedHikingSession(session: session, endedAt: capturedAt)
    }

    static func hasShareableRoute(in session: HikingSessionData) -> Bool {
        HikingSessionMetrics.resolvedDisplayRouteCoordinates(from: session).count >= 2
    }
}

/// 기록 중 카드 이미지 생성·사진 저장·시스템 공유. 세션을 일시정지/종료하지 않습니다.
@MainActor
final class MidHikeShareCoordinator: ObservableObject {
    enum PendingAction {
        case saveToPhotos
        case share
    }

    @Published var showsActionSheet = false
    @Published var pendingAction: PendingAction?
    @Published var progressOverlayMessage: String?
    @Published var alertMessage: String?
    @Published private(set) var isBusy = false

    private var workToken = UUID()
    private var activeTask: Task<Void, Never>?

    var isMenuBusy: Bool { isBusy || progressOverlayMessage != nil }

    func presentActionsIfPossible() {
        guard !isMenuBusy else {
            alertMessage = "이미지 생성 중입니다."
            return
        }

        let session = WorkoutManager.shared.sessionData
        guard session.state == .recording || session.state == .paused else { return }

        guard MidHikeShareSnapshot.hasShareableRoute(in: session) else {
            alertMessage = "경로가 조금 더 쌓이면 카드를 만들 수 있어요."
            return
        }

        pendingAction = nil
        showsActionSheet = true
    }

    func handleActionSheetDismissed() {
        guard let action = pendingAction else { return }
        pendingAction = nil

        switch action {
        case .saveToPhotos:
            beginExport(showsProgressCopy: "이미지 생성 중입니다.") { coordinator in
                await coordinator.saveCardToPhotos()
            }
        case .share:
            beginExport(showsProgressCopy: "이미지 생성 중입니다.") { coordinator in
                await coordinator.presentShareSheet()
            }
        }
    }

    func queueSaveToPhotos() {
        pendingAction = .saveToPhotos
        showsActionSheet = false
    }

    func queueShare() {
        pendingAction = .share
        showsActionSheet = false
    }

    /// 산행 종료가 우선 — 진행 중 렌더를 취소하고 결과는 버립니다.
    func cancelForWorkoutEnd() {
        workToken = UUID()
        activeTask?.cancel()
        activeTask = nil
        isBusy = false
        progressOverlayMessage = nil
        pendingAction = nil
        showsActionSheet = false
    }

    private func beginExport(
        showsProgressCopy: String,
        work: @escaping @MainActor (MidHikeShareCoordinator) async -> Void
    ) {
        guard !isBusy else {
            alertMessage = "이미지 생성 중입니다."
            return
        }

        let token = UUID()
        workToken = token
        isBusy = true
        progressOverlayMessage = showsProgressCopy

        activeTask = Task { @MainActor in
            defer {
                if workToken == token {
                    isBusy = false
                    progressOverlayMessage = nil
                    activeTask = nil
                }
            }
            await work(self)
        }
    }

    private func isWorkCurrent(_ token: UUID) -> Bool {
        workToken == token && !Task.isCancelled
    }

    private func captureCardImage(workToken token: UUID) async -> UIImage? {
        let liveSession = WorkoutManager.shared.sessionData
        guard liveSession.state == .recording || liveSession.state == .paused else { return nil }
        guard MidHikeShareSnapshot.hasShareableRoute(in: liveSession) else { return nil }

        let snapshotAt = Date()
        let record = MidHikeShareSnapshot.makeRecord(from: liveSession, capturedAt: snapshotAt)
        guard isWorkCurrent(token) else { return nil }

        let mapOptions = HikingShareExportPreferences.mapOptions
        let detailCanvas = HikingRecordStore.detailShareMapCanvasProvider?()
            ?? (
                size: HikingRecordShareDeviceMetrics.detailMapCanvasSize,
                pixelScale: HikingRecordShareDeviceMetrics.nativeScale
            )

        // 상세 LiveRouteMapSnapshotRegistry에 의존하지 않음 — 정적 generate.
        guard let routeImage = await HikingRouteSnapshotGenerator.generate(
            record: record,
            style: .routeOnly,
            mapOptions: mapOptions,
            canvasSize: detailCanvas.size,
            pixelScale: detailCanvas.pixelScale,
            reservesLegalAttributionStrip: true,
            allowLiveDetailCapture: false,
            preferSwiftUIMapTiles: true
        ) else {
            return nil
        }
        guard isWorkCurrent(token) else { return nil }

        let exportRouteImage = RouteMapOverlayMetrics.coveringNativeAppleMapsAttribution(on: routeImage)

        return HikingRecordShareComposer.render(
            record: record,
            routeImage: exportRouteImage,
            format: .fullScreen,
            isInProgressSnapshot: true
        )
    }

    private func presentShareSheet() async {
        let token = workToken
        guard let cardImage = await captureCardImage(workToken: token) else {
            guard isWorkCurrent(token) else { return }
            alertMessage = "공유할 항목을 만들지 못했습니다."
            return
        }
        guard isWorkCurrent(token) else { return }

        progressOverlayMessage = nil

        let shareTitle = WorkoutManager.shared.sessionData.effectiveStartedAt.map {
            $0.formatted(date: .abbreviated, time: .shortened)
        } ?? "산행 기록"

        let items: [Any] = [
            RecordCardShareActivityItem(image: cardImage, title: shareTitle)
        ]
        guard ActivitySharePresenter.present(items: items, mode: .recordCard) else {
            guard isWorkCurrent(token) else { return }
            alertMessage = "공유 화면을 열지 못했습니다."
            return
        }
    }

    private func saveCardToPhotos() async {
        let token = workToken
        guard let imageToSave = await captureCardImage(workToken: token) else {
            guard isWorkCurrent(token) else { return }
            alertMessage = "이미지를 만들지 못했습니다."
            return
        }
        guard isWorkCurrent(token) else { return }

        progressOverlayMessage = "사진 앱에 저장하는 중…"

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard isWorkCurrent(token) else { return }
        guard status == .authorized || status == .limited else {
            alertMessage = "사진 앱 접근 권한이 필요합니다."
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(
                    from: imageToSave.preparedForPhotoLibraryExport()
                )
            }
            guard isWorkCurrent(token) else { return }
            alertMessage = "지금까지의 기록 카드가 사진 앱에 저장되었습니다."
        } catch {
            guard isWorkCurrent(token) else { return }
            alertMessage = "저장에 실패했습니다."
        }
    }
}

#endif
