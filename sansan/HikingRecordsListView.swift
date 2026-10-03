//
//  HikingRecordsListView.swift
//  sansan
//

#if os(iOS)

import Photos
import SwiftUI
import UIKit
struct HikingRecordsListView: View {
    @ObservedObject private var store = HikingRecordStore.shared
    @ObservedObject private var routeFollow = HikingRouteFollowObserver.shared
    @ObservedObject private var watchInbox = WatchRecordInbox.shared
    @Environment(\.chromeCapsuleHeight) private var chromeCapsuleHeight
    var onFollowRoute: (() -> Void)? = nil

    @State private var selectedTab: RecordsListTab = .saved
    @State private var renamingRecordID: UUID?
    @State private var renameDraft = ""
    @State private var showsGPXPicker = false
    @State private var showsKMSCBrowser = false
    @State private var isImportingGPX = false
    @State private var gpxImportErrorMessage: String?
    @State private var pendingDeleteRecordIDs: [UUID] = []
    @State private var showsDeleteConfirmation = false
    @State private var isSelectingRecords = false
    @State private var selectedRecordIDs: Set<UUID> = []
    @State private var detailRoute: RecordDetailRoute?
    @State private var suppressRowNavigationUntil: Date = .distantPast
    @State private var cachedFavoriteRecords: [SavedHikingSession] = []
    @State private var cachedMainRecords: [SavedHikingSession] = []

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                switch selectedTab {
                case .saved:
                    savedRecordsTab
                case .imported:
                    importedRecordsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            recordsTabHeaderOverlay
        }
        .background {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        }
        .overlay(alignment: .bottom) {
            if isSelectingRecords {
                recordsSelectionBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, recordsListScrollBottomClearance)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isSelectingRecords)
        .navigationDestination(item: $detailRoute) { route in
            if let record = store.records.first(where: { $0.id == route.recordID }) {
                HikingRecordDetailView(record: record) {
                    beginFollowingRoute(recordID: record.id)
                }
            }
        }
        .navigationTitle("경로 모음")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isSelectingRecords {
                    Button("취소") {
                        exitSelectionMode()
                    }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !isSelectingRecords {
                    kmscBrowseToolbarButton
                    gpxImportToolbarButton
                }
            }
        }
        .onAppear {
            rebuildGroupedRecordCache()
            watchInbox.refreshCountFromDisk()
            if !store.hasCompletedInitialLoad {
                Task { await store.reloadForCurrentUserOffMain() }
            }
#if DEBUG
            applyAppStoreScreenshotModeIfNeeded()
#endif
        }
        .onChange(of: selectedTab) { _, _ in
            exitSelectionMode()
            detailRoute = nil
            rebuildGroupedRecordCache()
        }
        .onChange(of: store.records) { _, _ in
            rebuildGroupedRecordCache()
        }
        .sheet(isPresented: $showsGPXPicker) {
            GPXDocumentPickerSheet { url in
                Task { await importGPX(from: url) }
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsKMSCBrowser) {
            NavigationStack {
                KMSCCourseBrowseView {
                    showsKMSCBrowser = false
                    selectedTab = .imported
                    onFollowRoute?()
                }
            }
            .presentationDragIndicator(.visible)
        }
        .alert("GPX 가져오기 실패", isPresented: Binding(
            get: { gpxImportErrorMessage != nil },
            set: { isPresented in
                if !isPresented { gpxImportErrorMessage = nil }
            }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(gpxImportErrorMessage ?? "")
        }
        .sheet(isPresented: Binding(
            get: { renamingRecordID != nil },
            set: { isPresented in
                if !isPresented { renamingRecordID = nil }
            }
        )) {
            RecordRenameSheet(
                draft: $renameDraft,
                onSave: commitRenameDraft,
                onCancel: { renamingRecordID = nil }
            )
        }
        .alert("기록 삭제", isPresented: $showsDeleteConfirmation) {
            Button("삭제", role: .destructive) {
                confirmDeleteRecords()
            }
            Button("취소", role: .cancel) {
                pendingDeleteRecordIDs = []
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    private var deleteConfirmationMessage: String {
        let ids = pendingDeleteRecordIDs
        guard !ids.isEmpty else { return "이 기록을 삭제할까요?" }

        if ids.count == 1,
           let record = store.records.first(where: { $0.id == ids[0] }) {
            return "「\(record.listTitle)」을(를) 삭제할까요? 삭제한 기록은 복구할 수 없습니다."
        }

        return "\(ids.count)개 기록을 삭제할까요? 삭제한 기록은 복구할 수 없습니다."
    }

    private var savedRecords: [SavedHikingSession] {
        store.records.filter { !$0.isImported }
    }

    private var importedRecords: [SavedHikingSession] {
        store.records.filter(\.isImported)
    }

    private var recordsTabHeaderOverlayHeight: CGFloat {
        var height = chromeCapsuleHeight + iPhoneBottomChromeLayout.recordsTabBarVerticalPadding * 2
        if showsWatchSyncBanner {
            height += 12 + 36
        }
        if store.isGeneratingSnapshot || isImportingGPX {
            height += 12 + 36
        }
        return height
    }

    private var recordsListScrollBottomClearance: CGFloat {
        chromeCapsuleHeight + iPhoneBottomChromeLayout.chromeBottomInset + 4
    }

    private var recordsTabHeaderFadeHeight: CGFloat {
        recordsTabHeaderOverlayHeight + iPhoneBottomChromeLayout.recordsTabHeaderFadeExtension
    }

    private var recordsTabHeaderOverlay: some View {
        let navExtension = iPhoneBottomChromeLayout.inlineNavigationBarHeight

        return ZStack(alignment: .top) {
            recordsTabHeaderGradientBackdrop(navExtension: navExtension)

            // 페이드 구간까지 터치를 가로채면 리스트 첫 행(이름 수정 버튼)이 눌리지 않으므로
            // 스와이프 제스처는 헤더 콘텐츠 영역에만 붙입니다.
            VStack(spacing: 12) {
                RecordsListTabBar(
                    selection: $selectedTab,
                    savedCount: savedRecords.count,
                    importedCount: importedRecords.count
                )

                if showsWatchSyncBanner {
                    watchSyncBanner
                        .padding(.horizontal, iPhoneBottomChromeLayout.chromeHorizontalPadding)
                }

                if store.isGeneratingSnapshot || isImportingGPX {
                    recordsProgressBanner
                        .padding(.horizontal, iPhoneBottomChromeLayout.chromeHorizontalPadding)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: recordsTabHeaderOverlayHeight, alignment: .top)
            .contentShape(Rectangle())
            .gesture(recordsTabSwipeGesture)
        }
        .frame(maxWidth: .infinity)
        .frame(height: recordsTabHeaderFadeHeight, alignment: .top)
    }

    /// 상단 10%는 상단바와 동일한 불투명 바탕, 하단 90%는 투명으로 페이드.
    /// 내비게이션 타이틀 바 영역까지 위로 확장해 잘림 없이 이어지게 한다.
    private func recordsTabHeaderGradientBackdrop(navExtension: CGFloat) -> some View {
        let solidPortion = iPhoneBottomChromeLayout.recordsTabHeaderSolidPortion
        let totalHeight = recordsTabHeaderFadeHeight + navExtension

        return Color(.systemGroupedBackground)
            .frame(height: totalHeight)
            .frame(maxWidth: .infinity)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: solidPortion),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .offset(y: -navExtension)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    private var showsWatchSyncBanner: Bool {
        watchInbox.hasPending || watchInbox.isImporting
    }

    private static let watchSyncBannerColor = Color.orange

    private var watchSyncBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "applewatch")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Self.watchSyncBannerColor)

            Text(watchSyncBannerTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 0)

            if watchInbox.isImporting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("시작") {
                    Task { await watchInbox.importPending() }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Self.watchSyncBannerColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Self.watchSyncBannerColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !watchInbox.isImporting else { return }
            Task { await watchInbox.importPending() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(watchSyncBannerTitle)
        .accessibilityHint("워치 기록을 모음으로 가져옵니다.")
    }

    private var watchSyncBannerTitle: String {
        if watchInbox.isImporting {
            return "워치 기록 가져오는 중…"
        }
        if watchInbox.pendingCount == 1 {
            return "워치 기록 1건을 가져올 수 있습니다"
        }
        return "워치 기록 \(watchInbox.pendingCount)건을 가져올 수 있습니다"
    }

    private var recordsProgressBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(isImportingGPX ? "GPX 가져오는 중…" : "경로 이미지 생성 중…")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Color(.tertiarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private var recordsTabSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard abs(horizontal) > vertical, abs(horizontal) > 48 else { return }
                switchTab(withHorizontalTranslation: horizontal)
            }
    }

    private var savedRecordsTab: some View {
        Group {
            if !store.hasCompletedInitialLoad {
                recordsLoadingState
            } else if savedRecords.isEmpty {
                recordsEmptyState(
                    title: "내 경로 없음",
                    systemImage: "figure.hiking",
                    description: "등산 기록을 종료하면 여기에 저장됩니다."
                )
            } else {
                groupedRecordsList
            }
        }
    }

    private var importedRecordsTab: some View {
        Group {
            if !store.hasCompletedInitialLoad {
                recordsLoadingState
            } else if importedRecords.isEmpty {
                recordsEmptyState(
                    title: "불러온 경로 없음",
                    systemImage: "tray.and.arrow.down",
                    description: "GPX 파일을 가져오면 따라가기·상세 보기가 가능합니다.",
                    actions: {
                        gpxImportButton
                    }
                )
            } else {
                groupedRecordsList
            }
        }
    }

    @ViewBuilder
    private var groupedRecordsList: some View {
        List {
            if !cachedFavoriteRecords.isEmpty {
                Section {
                    ForEach(cachedFavoriteRecords) { record in
                        recordListRow(record, marker: .favorite)
                    }
                } header: {
                    Label("즐겨찾기", systemImage: "star.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
            }

            Section {
                ForEach(cachedMainRecords) { record in
                    recordListRow(
                        record,
                        marker: record.isListPinned ? .pinned : .none
                    )
                }
                .onDelete { offsets in
                    guard !isSelectingRecords else { return }
                    requestDeleteRecords(cachedMainRecords, at: offsets)
                }
            } header: {
                Text("전체")
            } footer: {
                if isSelectingRecords {
                    Text("항목을 탭해 선택을 추가하거나 해제할 수 있습니다.")
                } else {
                    Text("길게 눌러 여러 개를 선택하거나, 왼쪽으로 밀어 즐겨찾기·상단 고정·삭제, 오른쪽으로 밀면 따라가기가 나타납니다.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, recordsTabHeaderOverlayHeight, for: .scrollContent)
        .contentMargins(.bottom, recordsListScrollBottomClearance, for: .scrollContent)
        .ignoresSafeArea(edges: .bottom)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    private var recordsLoadingState: some View {
        ProgressView("경로 불러오는 중")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, recordsTabHeaderOverlayHeight)
    }

    private func recordsEmptyState(
        title: String,
        systemImage: String,
        description: String,
        @ViewBuilder actions: () -> some View = { EmptyView() }
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            actions()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, recordsTabHeaderOverlayHeight)
        .contentShape(Rectangle())
        .gesture(recordsTabSwipeGesture)
    }

    private func switchTab(withHorizontalTranslation horizontal: CGFloat) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            if horizontal < 0, selectedTab == .saved {
                selectedTab = .imported
            } else if horizontal > 0, selectedTab == .imported {
                selectedTab = .saved
            }
        }
    }

    private var kmscBrowseToolbarButton: some View {
        Button {
            showsKMSCBrowser = true
        } label: {
            toolbarTrailingIcon("map")
        }
        .accessibilityLabel("한국등산트레킹지원센터 제공 코스")
    }

    private var gpxImportToolbarButton: some View {
        Button {
            showsGPXPicker = true
        } label: {
            toolbarTrailingIcon("arrow.down.doc")
        }
        .disabled(isImportingGPX)
        .accessibilityLabel("GPX 가져오기")
    }

    /// SF Symbol마다 글리프 바운딩이 달라 높이 어긋남이 보이므로 동일 프레임으로 맞추고,
    /// 유리/캡슐 버튼 스타일에서 아이콘이 테두리에 붙지 않도록 좌우 여백을 둡니다.
    private func toolbarTrailingIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.body)
            .symbolRenderingMode(.monochrome)
            .frame(width: 22, height: 22)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
    }

    private var gpxImportButton: some View {
        Button {
            showsGPXPicker = true
        } label: {
            Label("GPX 가져오기", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.borderedProminent)
        .disabled(isImportingGPX)
    }

    private func beginFollowingRoute(recordID: UUID) {
        routeFollow.setFollowedRoute(recordID: recordID)
        onFollowRoute?()
    }

    private func requestDeleteRecords(_ records: [SavedHikingSession], at offsets: IndexSet) {
        let ids = offsets.compactMap { index -> UUID? in
            guard records.indices.contains(index) else { return nil }
            return records[index].id
        }
        requestDeleteRecords(ids: ids)
    }

    private func requestDeleteRecords(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        pendingDeleteRecordIDs = ids
        showsDeleteConfirmation = true
    }

    private func confirmDeleteRecords() {
        for id in pendingDeleteRecordIDs {
            store.delete(id: id)
        }
        pendingDeleteRecordIDs = []
        exitSelectionMode()
    }

    private func commitRenameDraft() {
        guard let id = renamingRecordID else { return }
        store.renameRecord(id: id, title: renameDraft)
        renamingRecordID = nil
    }

    private var currentTabRecordIDs: [UUID] {
        switch selectedTab {
        case .saved:
            savedRecords.map(\.id)
        case .imported:
            importedRecords.map(\.id)
        }
    }

    private func rebuildGroupedRecordCache() {
        let allRecords = selectedTab == .saved ? savedRecords : importedRecords
        cachedFavoriteRecords = SavedHikingSession.favoriteRecords(from: allRecords)
        cachedMainRecords = SavedHikingSession.mainListRecords(from: allRecords)
    }

    private var allRecordsInCurrentTabSelected: Bool {
        let ids = currentTabRecordIDs
        return !ids.isEmpty && ids.allSatisfy { selectedRecordIDs.contains($0) }
    }

    private func recordRowOpenGesture(recordID: UUID) -> some Gesture {
        TapGesture()
            .onEnded {
                openRecordDetail(recordID: recordID)
            }
            .exclusively(before: LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    enterSelectionMode(selecting: recordID)
                }
            )
    }

    private func enterSelectionMode(selecting recordID: UUID) {
        suppressRowNavigationUntil = Date().addingTimeInterval(0.35)
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelectingRecords = true
            selectedRecordIDs = [recordID]
        }
    }

    private func openRecordDetail(recordID: UUID) {
        guard Date() >= suppressRowNavigationUntil else { return }
        detailRoute = RecordDetailRoute(recordID: recordID)
    }

    private func exitSelectionMode() {
        isSelectingRecords = false
        selectedRecordIDs = []
    }

    private func toggleRecordSelection(_ recordID: UUID) {
        if selectedRecordIDs.contains(recordID) {
            selectedRecordIDs.remove(recordID)
            if selectedRecordIDs.isEmpty {
                exitSelectionMode()
            }
        } else {
            selectedRecordIDs.insert(recordID)
        }
    }

    private func selectAllRecordsInCurrentTab() {
        selectedRecordIDs = Set(currentTabRecordIDs)
    }

    private var recordsSelectionBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(RecordsListChrome.accent)

                Text("\(selectedRecordIDs.count)개 선택")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            Button {
                if allRecordsInCurrentTabSelected {
                    exitSelectionMode()
                } else {
                    selectAllRecordsInCurrentTab()
                }
            } label: {
                Label(
                    allRecordsInCurrentTabSelected ? "선택 해제" : "전체 선택",
                    systemImage: allRecordsInCurrentTabSelected ? "xmark.circle" : "checklist"
                )
                .font(.body.weight(.semibold))
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(RecordsListChrome.accent)
            .disabled(currentTabRecordIDs.isEmpty)

            Button(role: .destructive) {
                requestDeleteRecords(ids: Array(selectedRecordIDs))
            } label: {
                Label("삭제", systemImage: "trash")
                    .font(.body.weight(.semibold))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(selectedRecordIDs.isEmpty)
        }
        .frame(minHeight: 56)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: selectedRecordIDs.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: allRecordsInCurrentTabSelected)
    }

    @ViewBuilder
    private func recordListRow(
        _ record: SavedHikingSession,
        marker: HikingRecordRow.RecordListMarker = .none
    ) -> some View {
        if isSelectingRecords {
            Button {
                toggleRecordSelection(record.id)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: selectedRecordIDs.contains(record.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(
                            selectedRecordIDs.contains(record.id) ? RecordsListChrome.accent : Color.secondary
                        )

                    HikingRecordRow(
                        record: record,
                        listMarker: marker,
                        allowsRename: false,
                        onRename: {}
                    )
                }
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12))
        } else {
            HStack(alignment: .top, spacing: 4) {
                HikingRecordRow(
                    record: record,
                    listMarker: marker,
                    allowsRename: false,
                    onRename: {}
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(recordRowOpenGesture(recordID: record.id))

                Button {
                    renamingRecordID = record.id
                    renameDraft = record.listTitle
                } label: {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("기록 이름 수정")
                .padding(.top, 2)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 12))
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if record.session.points.count >= 2 {
                    Button {
                        beginFollowingRoute(recordID: record.id)
                    } label: {
                        Label("따라가기", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                    .tint(.orange)
                }
            }
            .modifier(RecordTrailingSwipeActions(record: record) { id in
                requestDeleteRecords(ids: [id])
            } togglePin: { id in
                store.toggleListPinned(id: id)
            } toggleFavorite: { id in
                store.toggleFavorite(id: id)
            })
        }
    }

    @MainActor
    private func importGPX(from url: URL) async {
        guard !isImportingGPX else { return }
        isImportingGPX = true
        defer { isImportingGPX = false }

        let result = await store.importGPX(from: url)
        switch result {
        case .success:
            selectedTab = .imported
        case .failure(let error):
            gpxImportErrorMessage = error.localizedDescription
        }
    }

#if DEBUG
    private func applyAppStoreScreenshotModeIfNeeded() {
        guard let mode = AppStoreScreenshotMode.current else { return }
        if let tab = mode.recordsListTab {
            selectedTab = tab
        }
        if mode.showsKMSCBrowser {
            showsKMSCBrowser = true
        }
    }
#endif
}
#Preview {
    NavigationStack {
        HikingRecordsListView()
    }
}


#endif
