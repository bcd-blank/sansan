//
//  HikingRecordDetailView.swift
//  sansan
//

#if os(iOS)

import SwiftUI

struct HikingRecordDetailView: View {
    let record: SavedHikingSession
    var onFollowRoute: () -> Void = {}

    @ObservedObject private var store = HikingRecordStore.shared
    @ObservedObject private var snapshotPreferences = HikingSnapshotPreferencesObserver.shared
    @StateObject private var export: HikingRecordExportCoordinator
    private var currentRecord: SavedHikingSession {
        export.currentRecord(fallback: record)
    }

    init(record: SavedHikingSession, onFollowRoute: @escaping () -> Void = {}) {
        self.record = record
        self.onFollowRoute = onFollowRoute
        _export = StateObject(wrappedValue: HikingRecordExportCoordinator(recordID: record.id))
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(geometry.size.width - HikingRecordCardLayout.detailContentWidthInset, 0)
            let mapHeight = HikingRecordCardLayout.detailMapHeight(
                contentWidth: contentWidth,
                viewportHeight: geometry.size.height
            )

            ScrollView {
                LazyVStack(spacing: HikingRecordCardLayout.detailSectionSpacing) {
                    HikingRecordTitleCard(
                        record: currentRecord,
                        compact: true,
                        showsProfileAvatar: true,
                        isMemoEditable: true,
                        onMemoCommit: { memo in
                            store.updateMemo(id: record.id, memo: memo)
                        }
                    )
                    .frame(maxWidth: .infinity)

                    if let weather = currentRecord.weather {
                        HikingRecordWeatherCard(weather: weather)
                            .frame(maxWidth: .infinity)
                    }

                    if contentWidth > 0, mapHeight > 0 {
                        HikingRecordRouteMapView(
                            recordID: record.id,
                            mapWidth: contentWidth,
                            mapHeight: mapHeight
                        )
                        .frame(maxWidth: .infinity)
                    }

                    HikingRecordSummarySection(record: currentRecord)

                    Color.clear
                        .frame(height: iPhoneBottomChromeLayout.scrollBottomClearance(hasWorkoutControls: false))
                }
                .padding(.horizontal, HikingRecordCardLayout.detailHorizontalPadding)
                .padding(.top, HikingRecordCardLayout.detailTopPadding)
            }
            .ignoresSafeArea(edges: .bottom)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
        .background {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        }
        .navigationTitle("기록 상세")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .overlay(alignment: .top) {
            if let status = export.menuStatusMessage(for: currentRecord) {
                MenuActionStatusBanner(message: status)
                    .padding(.horizontal, HikingRecordCardLayout.detailHorizontalPadding)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: export.menuStatusMessage(for: currentRecord))
        .overlay {
            if let progressOverlayMessage = export.progressOverlayMessage {
                RecordCardProgressOverlay(message: progressOverlayMessage)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: export.progressOverlayMessage)
        .fullScreenCover(isPresented: flythroughCoverBinding) {
            if FlythroughCapabilities.isFeatureEnabled {
                HikingFlythroughVideoView(
                    phase: export.flythroughPhase,
                    videoURL: export.flythroughVideoURL,
                    onCancel: { export.cancelFlythrough() },
                    onRetry: { export.startFlythrough(record: currentRecord) },
                    onClose: { export.cancelFlythrough() }
                )
                .interactiveDismissDisabled(flythroughBlocksInteractiveDismiss)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if export.isMenuBusy {
                    ProgressView()
                } else {
                    Button {
                        export.showsDetailActions = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body.weight(.medium))
                    }
                    .buttonStyle(ToolbarIconPressButtonStyle())
                }
            }
        }
        .sheet(isPresented: $export.showsDetailActions, onDismiss: {
            export.handleDetailActionsSheetDismissed(record: record, onFollowRoute: onFollowRoute)
        }) {
            HikingRecordDetailActionsSheet(
                isListPinned: currentRecord.isListPinned,
                isFavorite: currentRecord.isFavorite,
                isFollowDisabled: export.isMenuBusy || !export.hasShareableRoute(for: currentRecord),
                isRegenerateDisabled: export.isMenuBusy,
                isShareDisabled: export.isMenuBusy || !export.hasShareableRoute(for: currentRecord),
                isGPXShareDisabled: export.isMenuBusy || !export.canShareGPX(for: currentRecord),
                isSaveDisabled: export.isMenuBusy || !export.hasShareableRoute(for: currentRecord),
                onFollowRoute: { export.queueDetailAction(.followRoute) },
                onToggleListPinned: {
                    store.toggleListPinned(id: record.id)
                },
                onToggleFavorite: {
                    store.toggleFavorite(id: record.id)
                },
                onRegenerate: { export.queueDetailAction(.regenerateRouteImage) },
                onShare: { export.queueDetailAction(.shareCard) },
                onShareGPX: { export.queueDetailAction(.shareGPX) },
                onSaveToPhotos: { export.queueDetailAction(.saveToPhotos) },
                isFlythroughDisabled: export.isMenuBusy || !export.canMakeFlythrough(for: currentRecord),
                onMakeFlythrough: { export.queueDetailAction(.makeFlythrough) },
                onAppear: { Task { await export.prewarmExportImageWhenMapReady(record: currentRecord) } }
            )
        }
        .task(id: record.id) {
            await store.attachWeatherIfNeeded(for: record.id)
        }
        .onDisappear {
            export.cancelBackgroundWork()
        }
        .onChange(of: currentRecord.memo) { _, _ in
            export.invalidateCachedImages()
        }
        .onChange(of: currentRecord.weather?.changeSummary) { _, _ in
            export.invalidateCachedImages()
        }
        .alert("알림", isPresented: Binding(
            get: { export.saveAlertMessage != nil },
            set: { if !$0 { export.saveAlertMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(export.saveAlertMessage ?? "")
        }
        .onChange(of: snapshotPreferences.style) { _, _ in
            export.invalidateCachedImages()
        }
    }

    private var flythroughCoverBinding: Binding<Bool> {
        Binding(
            get: { FlythroughCapabilities.isFeatureEnabled && export.showsFlythrough },
            set: { isPresented in
                if !isPresented {
                    export.cancelFlythrough()
                }
            }
        )
    }

    private var flythroughBlocksInteractiveDismiss: Bool {
        switch export.flythroughPhase {
        case .finished, .failed:
            return false
        default:
            return true
        }
    }
}

#endif
