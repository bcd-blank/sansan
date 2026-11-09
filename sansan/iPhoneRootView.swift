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

/// 하단 글래스 크롬 — 9·15차: 모든 폭 한 줄, 시각 ×scale, 터치 ≥44 유지.
enum iPhoneBottomChromeLayout {
    /// A 기준 필요 폭(좌우 20 포함): 40+148.667+192+12.
    static let requiredWidth: CGFloat = 392.6666666667
    static let baseOuter: CGFloat = 64
    static let baseSide: CGFloat = 20
    static let baseTabItem: CGFloat = 72
    static let baseTabInset: CGFloat = 8
    static let baseSelectionInset: CGFloat = 6
    static let baseCircleGap: CGFloat = 4
    static let baseClusterGap: CGFloat = 8
    static let baseStartWidth: CGFloat = 127
    static let tabFontMin: CGFloat = 10
    static let minTouch: CGFloat = 44
    /// 화면 맨 아래에서 탭까지의 여백 — scale 미적용.
    static let chromeBottomInset: CGFloat = 26
    static let scrollEndBuffer: CGFloat = 16
    static let workoutStackSpacing: CGFloat = 10

    static func scale(forWidth width: CGFloat) -> CGFloat {
        min(1, width / requiredWidth)
    }

    /// scale1 기준 시각 높이(64). 좁은 폭에서는 64×scale.
    static func chromeControlHeight(forWidth width: CGFloat) -> CGFloat {
        baseOuter * scale(forWidth: width)
    }

    /// @deprecated 호환 — 폭을 모르는 호출부용 scale1.
    static let chromeControlHeight: CGFloat = baseOuter

    static func chromeHorizontalPadding(forWidth width: CGFloat) -> CGFloat {
        baseSide * scale(forWidth: width)
    }

    static let chromeHorizontalPadding: CGFloat = baseSide

    static func tabItemMinWidth(forWidth width: CGFloat) -> CGFloat {
        baseTabItem * scale(forWidth: width)
    }

    static let tabItemMinWidth: CGFloat = baseTabItem

    static func tabCapsuleInset(forWidth width: CGFloat) -> CGFloat {
        baseTabInset * scale(forWidth: width)
    }

    static let tabCapsuleInset: CGFloat = baseTabInset

    static func selectionInset(forWidth width: CGFloat) -> CGFloat {
        baseSelectionInset * scale(forWidth: width)
    }

    static let selectionInset: CGFloat = baseSelectionInset

    static func recordingPrimaryDiameter(forWidth width: CGFloat) -> CGFloat {
        baseOuter * scale(forWidth: width)
    }

    static func recordingOverflowHit(forWidth width: CGFloat) -> CGFloat {
        max(minTouch, recordingPrimaryDiameter(forWidth: width))
    }

    static func workoutControlSpacing(forWidth width: CGFloat) -> CGFloat {
        baseCircleGap * scale(forWidth: width)
    }

    static func chromeItemSpacing(forWidth width: CGFloat) -> CGFloat {
        baseClusterGap * scale(forWidth: width)
    }

    static let chromeItemSpacing: CGFloat = baseClusterGap

    static func tabLabelSize(forWidth width: CGFloat) -> CGFloat {
        max(tabFontMin, tabFontMin * scale(forWidth: width))
    }

    static func startLabelSize(forWidth width: CGFloat) -> CGFloat {
        15 * scale(forWidth: width)
    }

    static var tabRowHeight: CGFloat { chromeControlHeight }
    static var workoutControlsHeight: CGFloat { chromeControlHeight }

    /// 플로팅 크롬이 차지하는 세로 공간(오버레이용).
    static func floatingChromeHeight(forWidth width: CGFloat) -> CGFloat {
        chromeControlHeight(forWidth: width) + chromeBottomInset
    }

    static var floatingChromeHeight: CGFloat {
        chromeControlHeight + chromeBottomInset
    }

    static var chromeHeight: CGFloat { floatingChromeHeight }

    static func scrollBottomClearance(forWidth width: CGFloat) -> CGFloat {
        // 64×scale + 26 + 16. 안전 영역은 더하지 않음.
        floatingChromeHeight(forWidth: width) + scrollEndBuffer
    }

    static func scrollBottomClearance(hasWorkoutControls _: Bool = false) -> CGFloat {
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

    /// 메인/모음 탭 최소 터치 높이(HIG ≥44). 캡슐 시각 높이(`chromeControlHeight`)는 바꾸지 않습니다.
    static let tabHitMinHeight: CGFloat = 44
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
                WorkoutManager.shared.presentLayoutPreviewSummaryIfNeeded()
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
        case "recording", "recordingMore": return .recording
        case "paused": return .paused
        // summary는 fullScreenCover로 별도 표시 — 하단 크롬은 idle 유지.
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

    @State private var showMoreActions = false
    /// 측정 전엔 SE(375) 가정 — scale≈0.955. 넓은 값으로 시작하면 첫 프레임에 넘침.
    @State private var chromeWidth: CGFloat = 375

    private var controlHeight: CGFloat {
        iPhoneBottomChromeLayout.chromeControlHeight(forWidth: chromeWidth)
    }

    private var recordingPrimaryDiameter: CGFloat {
        iPhoneBottomChromeLayout.recordingPrimaryDiameter(forWidth: chromeWidth)
    }

    private var recordingOverflowHit: CGFloat {
        iPhoneBottomChromeLayout.recordingOverflowHit(forWidth: chromeWidth)
    }

    private var workoutControlSpacing: CGFloat {
        iPhoneBottomChromeLayout.workoutControlSpacing(forWidth: chromeWidth)
    }

    private var chromeScale: CGFloat {
        iPhoneBottomChromeLayout.scale(forWidth: chromeWidth)
    }

    var body: some View {
        HStack(alignment: .center, spacing: iPhoneBottomChromeLayout.chromeItemSpacing(forWidth: chromeWidth)) {
            iPhoneMainTabBar(
                selection: $selection,
                capsuleHeight: max(capsuleHeight, controlHeight),
                tabItemMinWidth: iPhoneBottomChromeLayout.tabItemMinWidth(forWidth: chromeWidth),
                tabLabelSize: iPhoneBottomChromeLayout.tabLabelSize(forWidth: chromeWidth),
                tabIconSize: 16 * chromeScale,
                tabCapsuleInset: iPhoneBottomChromeLayout.tabCapsuleInset(forWidth: chromeWidth),
                selectionInset: iPhoneBottomChromeLayout.selectionInset(forWidth: chromeWidth)
            )
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: iPhoneBottomChromeLayout.chromeItemSpacing(forWidth: chromeWidth))

            rightControls
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(controlHeight, iPhoneBottomChromeLayout.minTouch))
        // 좌측 탭과 동일 측 여백 — 종료도 우측 대칭. 좌우도 ×scale.
        .padding(.horizontal, iPhoneBottomChromeLayout.chromeHorizontalPadding(forWidth: chromeWidth))
        // iOS 26 liquid glass는 부모 opacity만으로 안 사라질 수 있어 합성 후 숨김.
        // 플로팅 More 시트 옆으로 종료 버튼이 비치지 않게 함.
        .compositingGroup()
        .opacity(showMoreActions ? 0 : 1)
        .allowsHitTesting(!showMoreActions)
        .accessibilityHidden(showMoreActions)
        .background {
            // padding 뒤 부착 → proxy.width ≈ 화면/컨테이너 논리 폭 (좌우 16pt 포함).
            GeometryReader { proxy in
                Color.clear
                    .onAppear { chromeWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in
                        chromeWidth = width
                    }
            }
        }
        .sheet(isPresented: $showMoreActions) {
            RecordingMoreActionsSheet(
                onTakePhoto: {
                    showMoreActions = false
                    onShowCamera()
                },
                onMakeRecordCard: {
                    showMoreActions = false
                    onShowMidHikeCard()
                }
            )
            // iOS 26: 불투명 Color 배경·커스텀 corner 대신 시스템 presentationBackground.
            // detent는 행 2개+취소에 맞춰 여백(회색 띠)을 줄입니다.
            .presentationDetents([.height(214)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
        }
        .task {
#if DEBUG
            // 레이아웃 검수: 더보기 시트를 자동으로 연다.
            guard ProcessInfo.processInfo.environment["SANSAN_LAYOUT_PREVIEW"] == "recordingMore" else { return }
            try? await Task.sleep(for: .milliseconds(600))
            showMoreActions = true
#endif
        }
    }

    @ViewBuilder
    private var rightControls: some View {
        switch sessionState {
        case .idle:
            startButton

        case .recording:
            recordingControls(
                primarySystemImage: "pause.fill",
                primaryTint: .orange,
                primaryLabel: "일시정지"
            ) {
                WorkoutManager.shared.pauseWorkout()
            }

        case .paused:
            recordingControls(
                primarySystemImage: "play.fill",
                primaryTint: .green,
                primaryLabel: "재개"
            ) {
                WorkoutManager.shared.resumeWorkout()
            }
        }
    }

    private func recordingControls(
        primarySystemImage: String,
        primaryTint: Color,
        primaryLabel: String,
        primaryAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: workoutControlSpacing) {
            moreButton
            workoutGlassButton(
                systemImage: primarySystemImage,
                tint: primaryTint,
                label: primaryLabel,
                diameter: recordingPrimaryDiameter,
                action: primaryAction
            )
            workoutGlassButton(
                systemImage: "stop.fill",
                tint: .red,
                label: "종료",
                diameter: recordingPrimaryDiameter,
                action: onShowEndConfirmation
            )
        }
    }

    private var startButton: some View {
        let title = isStartCountdownActive ? "기록 준비중" : "기록 시작"
        let label = iPhoneBottomChromeLayout.startLabelSize(forWidth: chromeWidth)
        let icon = 15 * chromeScale
        return Button(action: onStartWorkout) {
            HStack(spacing: 8 * chromeScale) {
                if isStartCountdownActive {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .frame(width: icon, height: icon)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: label, weight: .bold))
                        .frame(width: icon, height: icon)
                }

                Text(title)
                    .font(.system(size: label, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 12 * chromeScale)
            .frame(height: controlHeight)
            .frame(minHeight: iPhoneBottomChromeLayout.minTouch)
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

    /// ⋯ 더보기 — 사진·카드(기록 중 이미지 저장) 보조 진입점. hit ≥44, 시각 가중치는 한 단계 낮춤.
    private var moreButton: some View {
        Button {
            showMoreActions = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Circle())
        }
        .frame(width: recordingOverflowHit, height: recordingOverflowHit)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("더보기")
    }

    private func workoutGlassButton(
        systemImage: String,
        tint: Color,
        label: String,
        diameter: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: max(14, diameter * 0.34), weight: .bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // glassProminent가 고유 패딩으로 커지지 않도록 외곽을 ⌀에 고정합니다.
        .frame(width: diameter, height: diameter)
        .buttonStyle(.glassProminent)
        .tint(tint)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }
}

private struct iPhoneMainTabBar: View {
    @Binding var selection: iPhoneMainTab
    var capsuleHeight: CGFloat
    var tabItemMinWidth: CGFloat = iPhoneBottomChromeLayout.tabItemMinWidth
    var tabLabelSize: CGFloat = 10
    var tabIconSize: CGFloat = 16
    var tabCapsuleInset: CGFloat = iPhoneBottomChromeLayout.tabCapsuleInset
    var selectionInset: CGFloat = iPhoneBottomChromeLayout.selectionInset
    @Namespace private var selectionNamespace

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
            // 시각 높이는 scale, 터치는 ≥44pt.
            .frame(height: max(tabContentHeight, iPhoneBottomChromeLayout.tabHitMinHeight))
            .padding(.horizontal, tabCapsuleInset)
            .frame(height: capsuleHeight)
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("navigationTabs", in: selectionNamespace)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: max(capsuleHeight, iPhoneBottomChromeLayout.tabHitMinHeight))
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
            VStack(spacing: 2 * (tabIconSize / 16)) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: tabIconSize, weight: isSelected ? .semibold : .medium))
                    .symbolVariant(isSelected ? .fill : .none)

                Text(tab.title)
                    .font(.system(size: tabLabelSize, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            // 아이콘·글자 묶음 시각 크기는 그대로 두고, 히트만 44pt 이상으로 키웁니다.
            .frame(minWidth: tabItemMinWidth, minHeight: tabContentHeight)
            .frame(minWidth: tabItemMinWidth, minHeight: iPhoneBottomChromeLayout.tabHitMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 선택 하이라이트를 버튼 자체에 붙여 아이콘과 중심이 항상 일치하도록 합니다.
        .background {
            if isSelected {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                    .padding(max(0, selectionInset - tabCapsuleInset))
                    .matchedGeometryEffect(id: "tabSelectionHighlight", in: selectionNamespace)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(tab.title)
    }
}

/// 기록 중 더보기 — 아이콘 + 제목 + 한 줄 부제.
/// iOS 26 시트는 시스템 liquid glass를 쓰고, 불투명 grouped/카드 fill은 넣지 않습니다
/// (하단 크롬 위에 회색 띠가 갈라져 보이던 원인).
private struct RecordingMoreActionsSheet: View {
    var onTakePhoto: () -> Void
    var onMakeRecordCard: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("더보기")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                moreRow(
                    systemImage: "camera.fill",
                    tint: .blue,
                    title: "사진 찍기",
                    subtitle: "카메라로 기록에 추가",
                    action: onTakePhoto
                )
                Divider()
                    .padding(.leading, 66)
                moreRow(
                    systemImage: "doc.richtext",
                    tint: .indigo,
                    title: "기록 카드 만들기",
                    subtitle: "지금까지 이미지 저장·공유",
                    action: onMakeRecordCard
                )
            }
            .padding(.horizontal, 12)

            Button("취소", role: .cancel) {
                dismiss()
            }
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 8)
        // 시스템 presentationBackground(liquid glass)만 사용 — 커스텀 fill 금지.
    }

    private func moreRow(
        systemImage: String,
        tint: Color,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
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
