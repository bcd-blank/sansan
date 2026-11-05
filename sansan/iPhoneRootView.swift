//
//  iPhoneRootView.swift
//  sansan
//

#if os(iOS)

import SwiftUI

private enum iPhoneMainTab: Int, CaseIterable, Hashable {
    case dashboard = 0
    case records = 1

    var title: String {
        switch self {
        case .dashboard: "메인"
        case .records: "모음"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "figure.hiking"
        case .records: "rectangle.stack"
        }
    }
}

/// 하단 글래스 크롬 — 스크롤 여백·오버레이 위치 계산용.
enum iPhoneBottomChromeLayout {
    /// 탭·기록 시작·기록 중 버튼 공통 터치 높이.
    static let chromeControlHeight: CGFloat = 50
    /// 화면 맨 아래에서 탭까지의 여백 — 홈 인디케이터(시스템 제스처 바)를 비키도록 충분히 확보.
    static let chromeBottomInset: CGFloat = 26
    static let workoutStackSpacing: CGFloat = 10
    static let tabCapsuleInset: CGFloat = 8
    static let selectionInset: CGFloat = 6
    static let tabItemMinWidth: CGFloat = 76
    /// 기록 중·일시정지 — 4버튼(사진·카드·일시정지/재개·종료)이 SE(375)에도 들어가도록 축소.
    static let compactTabItemMinWidth: CGFloat = 58
    /// 기록 중 우측 컨트롤 버튼 크기.
    static let compactControlHeight: CGFloat = 40
    static let chromeHorizontalPadding: CGFloat = 16
    static let chromeItemSpacing: CGFloat = 8
    static let workoutControlSpacing: CGFloat = 6
    /// 기록 중 4버튼 간격 — 좁은 폭에서 탭 캡슐과 겹치지 않게 조금 더 촘촘히.
    static let compactWorkoutControlSpacing: CGFloat = 4
    static let scrollEndBuffer: CGFloat = 16

    static var tabRowHeight: CGFloat { chromeControlHeight }
    static var workoutControlsHeight: CGFloat { chromeControlHeight }

    /// 플로팅 크롬이 차지하는 세로 공간(오버레이용).
    static var floatingChromeHeight: CGFloat {
        chromeControlHeight + chromeBottomInset
    }

    static var chromeHeight: CGFloat { floatingChromeHeight }

    static func scrollBottomClearance(hasWorkoutControls _: Bool = false) -> CGFloat {
        // 기록 컨트롤이 탭과 같은 행을 공유하므로 크롬 높이는 상태와 무관하게 일정하다.
        floatingChromeHeight + scrollEndBuffer
    }

    /// 모음 리스트 하단 여백 — 하단 크롬 높이만큼만 확보.
    static var recordsListScrollBottomClearance: CGFloat {
        floatingChromeHeight + 4
    }

    /// 모음 화면 상단 플로팅 탭 캡슐(내 경로/불러온 경로) 세로 패딩.
    static let recordsTabBarVerticalPadding: CGFloat = 8

    static func tabContentHeight(forCapsuleHeight capsuleHeight: CGFloat) -> CGFloat {
        capsuleHeight - tabCapsuleInset * 2
    }
    /// 탭 캡슐 아래/위로 이어지는 그라데이션 페이드 추가 높이.
    static let recordsTabHeaderFadeExtension: CGFloat = 72
    /// 페이드 끝단 불투명 구간 비율(0~1). 0.1 = 끝 10%는 바탕색 고정.
    static let recordsTabHeaderSolidPortion: CGFloat = 0.1
    /// inline 내비게이션 타이틀 바 콘텐츠 높이.
    static let inlineNavigationBarHeight: CGFloat = 44

    /// 하단 메인/모음 크롬 그라데이션 페이드 전체 높이.
    static var bottomChromeFadeHeight: CGFloat {
        floatingChromeHeight + recordsTabHeaderFadeExtension
    }
}

private struct ChromeCapsuleHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ChromeCapsuleHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = iPhoneBottomChromeLayout.chromeControlHeight
}

extension EnvironmentValues {
    var chromeCapsuleHeight: CGFloat {
        get { self[ChromeCapsuleHeightKey.self] }
        set { self[ChromeCapsuleHeightKey.self] = newValue }
    }
}

/// 요약 전체 화면 — `summarySession`이 레이스로 nil이 되어도 빈 흰 커버가 뜨지 않도록 값을 캡처합니다.
private struct WorkoutSummaryCoverItem: Identifiable, Sendable {
    let id: UUID
    let session: HikingSessionData

    nonisolated init(_ session: HikingSessionData) {
        id = session.sessionID
        self.session = session
    }
}

/// iPhone 앱 루트 — 메인·모음 탭, 좌우 스와이프·하단 탭으로 전환.
struct iPhoneRootView: View {
    @ObservedObject private var chrome = WorkoutChromeStateObserver.shared
    @StateObject private var midHikeShare = MidHikeShareCoordinator()
    @State private var selectedTab: iPhoneMainTab = .dashboard

    private var selectedTabBinding: Binding<iPhoneMainTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == .records {
                    isRecordsTabPrepared = true
                }
                selectedTab = newValue
            }
        )
    }
    @State private var showEndConfirmation = false
    @State private var showCamera = false
    @State private var photoCaptureFailed = false
    @State private var locationPermissionAlert: LocationPermissionAlert?
    @State private var pendingStartWorkout = false
    @State private var chromeCapsuleHeight = iPhoneBottomChromeLayout.chromeControlHeight
    /// 첫 프레임에서 모음 리스트·썸네일까지 만들지 않아 메인 지도·버튼이 먼저 살아나게 합니다.
    @State private var isRecordsTabPrepared = false

    private var summaryCoverItem: Binding<WorkoutSummaryCoverItem?> {
        Binding(
            get: { chrome.summarySession.map(WorkoutSummaryCoverItem.init) },
            set: { _ in
                // 스와이프 dismiss 비활성 — 저장/삭제로만 닫습니다.
            }
        )
    }

    var body: some View {
        mainTabStack
            .onPreferenceChange(ChromeCapsuleHeightPreferenceKey.self) { height in
                if height > 0 {
                    chromeCapsuleHeight = height
                }
            }
#if DEBUG
            .onAppear {
                applyAppStoreScreenshotModeIfNeeded()
                exportLayoutPreviewCardIfNeeded()
            }
#endif
            .environment(\.chromeCapsuleHeight, chromeCapsuleHeight)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .ignoresSafeArea(.container, edges: .bottom)
            .fullScreenCover(item: summaryCoverItem) { item in
                WorkoutSummaryView(
                    session: item.session,
                    onSave: { WorkoutManager.shared.confirmSummary() },
                    onDiscard: { WorkoutManager.shared.discardSummary() }
                )
                .environment(\.chromeCapsuleHeight, chromeCapsuleHeight)
            }
            .fullScreenCover(isPresented: $showCamera) {
                TrailPhotoCameraPicker { image in
                    Task {
                        if !(await WorkoutManager.shared.addTrailPhoto(image)) {
                            photoCaptureFailed = true
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .confirmationDialog(
                "기록을 종료할까요?",
                isPresented: $showEndConfirmation,
                titleVisibility: .visible
            ) {
                Button("종료", role: .destructive) {
                    midHikeShare.cancelForWorkoutEnd()
                    WorkoutManager.shared.endWorkout()
                }
                Button("취소", role: .cancel) {}
            }
            .confirmationDialog(
                "지금까지의 기록",
                isPresented: $midHikeShare.showsActionSheet,
                titleVisibility: .visible
            ) {
                Button("사진 앱에 저장") {
                    midHikeShare.queueSaveToPhotos()
                }
                Button("공유하기") {
                    midHikeShare.queueShare()
                }
                Button("취소", role: .cancel) {
                    midHikeShare.pendingAction = nil
                }
            }
            .onChange(of: midHikeShare.showsActionSheet) { _, isPresented in
                if !isPresented {
                    midHikeShare.handleActionSheetDismissed()
                }
            }
            .overlay {
                if let progressOverlayMessage = midHikeShare.progressOverlayMessage {
                    RecordCardProgressOverlay(message: progressOverlayMessage)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: midHikeShare.progressOverlayMessage)
            .alert("사진 저장 실패", isPresented: $photoCaptureFailed) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("GPS 위치를 확인한 뒤 다시 시도해 주세요.")
            }
            .alert("알림", isPresented: Binding(
                get: { midHikeShare.alertMessage != nil },
                set: { if !$0 { midHikeShare.alertMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(midHikeShare.alertMessage ?? "")
            }
            .onChange(of: chrome.sessionState) { _, state in
                if state == .idle {
                    midHikeShare.cancelForWorkoutEnd()
                }
            }
            .locationPermissionAlerts(
                workout: WorkoutManager.shared,
                alert: $locationPermissionAlert,
                pendingStartWorkout: $pendingStartWorkout
            )
            .onChange(of: chrome.shouldPresentRecordsList) { _, shouldShow in
                if shouldShow {
                    isRecordsTabPrepared = true
                    selectedTab = .records
                    WorkoutManager.shared.clearPendingRecordsPresentation()
                }
            }
            .onChange(of: selectedTab) { _, tab in
                if tab == .records {
                    isRecordsTabPrepared = true
                    WorkoutManager.shared.cancelStartCountdown()
                }
            }
            .onChange(of: chrome.startCountdownRemaining) { _, countdown in
                if countdown != nil {
                    selectedTab = .dashboard
                }
            }
    }

    private var mainTabStack: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                iPhoneDashboardView()
                    .opacity(selectedTab == .dashboard ? 1 : 0)
                    .allowsHitTesting(selectedTab == .dashboard)
                    .accessibilityHidden(selectedTab != .dashboard)
                    .zIndex(selectedTab == .dashboard ? 1 : 0)

                if isRecordsTabPrepared {
                    NavigationStack {
                        HikingRecordsListView {
                            selectedTab = .dashboard
                        }
                    }
                    .opacity(selectedTab == .records ? 1 : 0)
                    .allowsHitTesting(selectedTab == .records)
                    .accessibilityHidden(selectedTab != .records)
                    .zIndex(selectedTab == .records ? 1 : 0)
                }
            }

            // 카운트다운 검정 오버레이 위에 밝은 페이드가 떠 보이지 않도록 숨긴다.
            iPhoneBottomChromeGradientBackdrop()
                .opacity(chrome.startCountdownRemaining == nil ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: chrome.startCountdownRemaining == nil)

            iPhoneBottomChrome(
                selection: selectedTabBinding,
                sessionState: layoutPreviewSessionState ?? chrome.sessionState,
                isStartCountdownActive: chrome.startCountdownRemaining != nil,
                capsuleHeight: chromeCapsuleHeight,
                onStartWorkout: handleStartWorkoutTap,
                onShowCamera: { showCamera = true },
                onShowMidHikeCard: { midHikeShare.presentActionsIfPossible() },
                onShowEndConfirmation: { showEndConfirmation = true }
            )
            .padding(.bottom, iPhoneBottomChromeLayout.chromeBottomInset)
        }
    }

    /// DEBUG/`SANSAN_LAYOUT_PREVIEW` — 기록·일시정지 크롬만 강제해 시뮬레이터 레이아웃 점검.
    private var layoutPreviewSessionState: HikingSessionState? {
#if DEBUG
        switch ProcessInfo.processInfo.environment["SANSAN_LAYOUT_PREVIEW"] {
        case "recording": return .recording
        case "paused": return .paused
        default: return nil
        }
#else
        nil
#endif
    }

    private func handleStartWorkoutTap() {
        selectedTab = .dashboard
        LocationPermissionHandling.handleWorkoutStartTap(
            workout: WorkoutManager.shared,
            alert: &locationPermissionAlert,
            pendingStartWorkout: &pendingStartWorkout
        )
    }
}

// MARK: - Bottom chrome gradient

/// 하단 메인/모음 탭 뒤 그라데이션 — 상단 모음 탭 페이드와 대칭.
private struct iPhoneBottomChromeGradientBackdrop: View {
    @Environment(\.chromeCapsuleHeight) private var capsuleHeight

    private let solidPortion = iPhoneBottomChromeLayout.recordsTabHeaderSolidPortion

    private var fadeHeight: CGFloat {
        capsuleHeight
            + iPhoneBottomChromeLayout.chromeBottomInset
            + iPhoneBottomChromeLayout.recordsTabHeaderFadeExtension
    }

    var body: some View {
        Color(.systemGroupedBackground)
            .frame(height: fadeHeight)
            .frame(maxWidth: .infinity)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: solidPortion),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            }
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
    }
}

// MARK: - Bottom chrome (Photos-style tab bar + actions)

private struct iPhoneBottomChrome: View {
    @Binding var selection: iPhoneMainTab
    var sessionState: HikingSessionState
    var isStartCountdownActive: Bool
    var capsuleHeight: CGFloat
    var onStartWorkout: () -> Void
    var onShowCamera: () -> Void
    var onShowMidHikeCard: () -> Void
    var onShowEndConfirmation: () -> Void

    private let controlHeight = iPhoneBottomChromeLayout.chromeControlHeight

    private var isCompact: Bool {
        sessionState != .idle
    }

    private var workoutControlSize: CGFloat {
        isCompact ? iPhoneBottomChromeLayout.compactControlHeight : controlHeight
    }

    private var tabItemMinWidth: CGFloat {
        isCompact
            ? iPhoneBottomChromeLayout.compactTabItemMinWidth
            : iPhoneBottomChromeLayout.tabItemMinWidth
    }

    private var activeWorkoutControlSpacing: CGFloat {
        isCompact
            ? iPhoneBottomChromeLayout.compactWorkoutControlSpacing
            : iPhoneBottomChromeLayout.workoutControlSpacing
    }

    var body: some View {
        HStack(alignment: .center, spacing: iPhoneBottomChromeLayout.chromeItemSpacing) {
            iPhoneMainTabBar(
                selection: $selection,
                capsuleHeight: capsuleHeight,
                tabItemMinWidth: tabItemMinWidth
            )
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: iPhoneBottomChromeLayout.chromeItemSpacing)

            rightControls
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(height: capsuleHeight)
        .padding(.horizontal, iPhoneBottomChromeLayout.chromeHorizontalPadding)
    }

    @ViewBuilder
    private var rightControls: some View {
        switch sessionState {
        case .idle:
            startButton

        case .recording:
            HStack(spacing: activeWorkoutControlSpacing) {
                photoButton
                cardButton
                workoutGlassButton(systemImage: "pause.fill", tint: .orange, label: "일시정지") {
                    WorkoutManager.shared.pauseWorkout()
                }
                endButton
            }

        case .paused:
            HStack(spacing: activeWorkoutControlSpacing) {
                photoButton
                cardButton
                workoutGlassButton(systemImage: "play.fill", tint: .green, label: "재개") {
                    WorkoutManager.shared.resumeWorkout()
                }
                endButton
            }
        }
    }

    private var startButton: some View {
        let title = isStartCountdownActive ? "기록 준비중" : "기록 시작"
        return Button(action: onStartWorkout) {
            HStack(spacing: 8) {
                if isStartCountdownActive {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .frame(width: 15, height: 15)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 15, height: 15)
                }

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: controlHeight)
        }
        .buttonStyle(.glassProminent)
        .tint(isStartCountdownActive ? .orange : .green)
        .buttonBorderShape(.capsule)
        .allowsHitTesting(!isStartCountdownActive)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ChromeCapsuleHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
        .accessibilityLabel(title)
    }

    private var photoButton: some View {
        workoutGlassButton(systemImage: "camera.fill", tint: .blue, label: "사진", action: onShowCamera)
    }

    private var cardButton: some View {
        // 완료 후 공유(square.and.arrow.up)와 구분 — 기록 중 카드 스냅샷 진입점.
        workoutGlassButton(
            systemImage: "doc.richtext",
            tint: .indigo,
            label: "카드",
            action: onShowMidHikeCard
        )
    }

    private var endButton: some View {
        workoutGlassButton(systemImage: "stop.fill", tint: .red, label: "종료", action: onShowEndConfirmation)
    }

    private func workoutGlassButton(
        systemImage: String,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .frame(width: workoutControlSize, height: workoutControlSize)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.small)
        .tint(tint)
        .buttonBorderShape(.circle)
        .fixedSize()
        .accessibilityLabel(label)
    }
}

private struct iPhoneMainTabBar: View {
    @Binding var selection: iPhoneMainTab
    var capsuleHeight: CGFloat
    var tabItemMinWidth: CGFloat = iPhoneBottomChromeLayout.tabItemMinWidth
    @Namespace private var selectionNamespace

    private let tabCapsuleInset = iPhoneBottomChromeLayout.tabCapsuleInset
    private let selectionInset = iPhoneBottomChromeLayout.selectionInset

    private var tabContentHeight: CGFloat {
        iPhoneBottomChromeLayout.tabContentHeight(forCapsuleHeight: capsuleHeight)
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(iPhoneMainTab.allCases, id: \.self) { tab in
                    tabButton(for: tab)
                        .glassEffectID(tab, in: selectionNamespace)
                }
            }
            .frame(height: tabContentHeight)
            .padding(tabCapsuleInset)
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("navigationTabs", in: selectionNamespace)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: capsuleHeight)
    }

    @ViewBuilder
    private func tabButton(for tab: iPhoneMainTab) -> some View {
        let isSelected = selection == tab

        Button {
            guard selection != tab else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                    .symbolVariant(isSelected ? .fill : .none)

                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .frame(minWidth: tabItemMinWidth, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 선택 하이라이트를 버튼 자체에 붙여 아이콘과 중심이 항상 일치하도록 합니다.
        .background {
            if isSelected {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .padding(selectionInset - tabCapsuleInset)
                    .matchedGeometryEffect(id: "tabSelectionHighlight", in: selectionNamespace)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
private extension iPhoneRootView {
    func applyAppStoreScreenshotModeIfNeeded() {
        guard let mode = AppStoreScreenshotMode.current, mode.opensRecordsTab else { return }
        isRecordsTabPrepared = true
        selectedTab = .records
    }

    /// `SANSAN_LAYOUT_PREVIEW=cardExport` — 극단 폭 점검용 fullScreen 카드 PNG를 Documents에 저장.
    func exportLayoutPreviewCardIfNeeded() {
        guard ProcessInfo.processInfo.environment["SANSAN_LAYOUT_PREVIEW"] == "cardExport" else { return }
        Task { @MainActor in
            let started = Date().addingTimeInterval(-3_600)
            let p0 = HikingPoint(
                latitude: 37.5665,
                longitude: 126.9780,
                altitude: 40,
                timestamp: started
            )
            let p1 = HikingPoint(
                latitude: 37.5700,
                longitude: 126.9850,
                altitude: 220,
                timestamp: started.addingTimeInterval(3_600)
            )
            var session = HikingSessionData(
                state: .recording,
                startedAt: started,
                totalDistance: 4_250,
                elapsedTime: 3_600,
                currentAltitude: 220,
                points: [p0, p1],
                stepCount: 5_400,
                activeEnergyKilocalories: 320,
                elevationGainMeters: 180
            )
            session.elevationProfile = [
                HikingElevationChartSample(id: UUID(), distanceMeters: 0, altitude: 40),
                HikingElevationChartSample(id: UUID(), distanceMeters: 2_100, altitude: 160),
                HikingElevationChartSample(id: UUID(), distanceMeters: 4_250, altitude: 220),
            ]
            let record = MidHikeShareSnapshot.makeRecord(from: session, capturedAt: Date())
            let mapSize = HikingRecordShareDeviceMetrics.detailMapCanvasSize
            let format = UIGraphicsImageRendererFormat()
            format.scale = HikingRecordShareDeviceMetrics.nativeScale
            format.opaque = true
            let routeImage = UIGraphicsImageRenderer(size: mapSize, format: format).image { ctx in
                UIColor.secondarySystemFill.setFill()
                ctx.fill(CGRect(origin: .zero, size: mapSize))
                UIColor.systemGreen.setStroke()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: mapSize.width * 0.18, y: mapSize.height * 0.72))
                path.addLine(to: CGPoint(x: mapSize.width * 0.48, y: mapSize.height * 0.42))
                path.addLine(to: CGPoint(x: mapSize.width * 0.78, y: mapSize.height * 0.28))
                path.lineWidth = 4
                path.stroke()
            }
            guard let card = HikingRecordShareComposer.render(
                record: record,
                routeImage: routeImage,
                format: .fullScreen,
                isInProgressSnapshot: true
            ) else { return }
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = dir.appendingPathComponent("mid-hike-layout-card.png")
            try? card.pngData()?.write(to: url, options: .atomic)
        }
    }
}
#endif

#endif
