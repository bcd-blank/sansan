//
//  WatchWorkoutView.swift
//  sansan Watch App
//

import SwiftUI
import WatchKit

struct WatchWorkoutView: View {
    @EnvironmentObject private var workout: WorkoutManager
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = WatchWorkoutTab.controls.rawValue
    @State private var showEndConfirmation = false
    @State private var locationPermissionAlert: LocationPermissionAlert?
    @State private var pendingStartWorkout = false

    private var timerRefreshInterval: TimeInterval {
        isLuminanceReduced ? 10 : 1
    }

    private var isShowingSummary: Binding<Bool> {
        Binding(
            get: { workout.summarySession != nil },
            set: { _ in }
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            controlsPage
                .tag(WatchWorkoutTab.controls.rawValue)
            metricsPage
                .tag(WatchWorkoutTab.metrics.rawValue)
        }
        .tabViewStyle(.verticalPage)
        .sheet(isPresented: isShowingSummary) {
            if let summary = workout.summarySession {
                WatchWorkoutSummaryView(
                    session: summary,
                    onSave: { workout.confirmSummary() },
                    onDiscard: { workout.discardSummary() }
                )
            }
        }
        .onAppear {
            workout.setWatchDisplayLuminanceReduced(isLuminanceReduced)
            workout.syncWatchRuntimeOnAppear()
            selectedTab = preferredTab(for: workout.sessionData.state)
            Task {
                await workout.prepareWatchWorkoutRuntime()
            }
#if DEBUG
            // 시뮬레이터 재현용 자동 시작 훅 — SANSAN_AUTOSTART=1 환경 변수로만 동작합니다.
            if ProcessInfo.processInfo.environment["SANSAN_AUTOSTART"] == "1" {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    workout.startWorkout()
                }
            }
#endif
        }
        .onChange(of: isLuminanceReduced) { _, reduced in
            workout.setWatchDisplayLuminanceReduced(reduced)
            guard !reduced else { return }
            selectedTab = preferredTab(for: workout.sessionData.state)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            workout.kickWatchConnectivityHandshake()
        }
        .onChange(of: workout.sessionData.state) { oldState, newState in
            // 기록 시작 시 데이터 화면으로, 종료(대기 복귀) 시 컨트롤 화면으로 전환.
            if oldState == .idle, newState == .recording {
                selectedTab = WatchWorkoutTab.metrics.rawValue
            } else if newState == .idle {
                selectedTab = WatchWorkoutTab.controls.rawValue
            }
        }
        .background(Color.black)
        .overlay {
            if let count = workout.startCountdownRemaining {
                startCountdownOverlay(count)
            }
        }
        .onChange(of: workout.startCountdownRemaining) { _, newValue in
            if newValue != nil {
                WatchHaptics.click()
            } else if workout.sessionData.state == .recording {
                WatchHaptics.start()
            }
        }
        .watchResumeHikingPromptAlert(workout: workout)
        .locationPermissionAlerts(
            workout: workout,
            alert: $locationPermissionAlert,
            pendingStartWorkout: $pendingStartWorkout
        )
    }

    // MARK: - 시작 카운트다운

    private func startCountdownOverlay(_ count: Int) -> some View {
        GeometryReader { geometry in
            let layout = WatchScreenLayout(size: geometry.size)
            ZStack {
                Color.black.ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 6 * layout.scale) {
                    Text("\(count)")
                        .font(.system(size: layout.countdownFontSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(.green)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: count)

                    Text("등산을 시작합니다")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button("취소") {
                        WatchHaptics.click()
                        workout.cancelStartCountdown()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: - 메인 데이터

    private static let liveRouteGreen = Color(red: 0.12, green: 0.72, blue: 0.45)

    /// 데이터 화면 1열 카드 목록.
    private var metricItems: [WatchMetricItem] {
        [
            WatchMetricItem(title: "심박수", value: heartRateValueText, unit: "bpm", icon: "heart.fill", tint: .pink, valueColor: heartRateValueColor),
            WatchMetricItem(title: "거리", value: formattedDistance, unit: "km", icon: "figure.hiking", tint: Self.liveRouteGreen),
            WatchMetricItem(title: "고도", value: formattedAltitude, unit: "m", icon: "mountain.2.fill", tint: .cyan),
            WatchMetricItem(title: "상승", value: formattedElevationGain, unit: "m↑", icon: "arrow.up.right", tint: .orange),
            WatchMetricItem(title: "평균속도", value: formattedPace, unit: "", icon: "speedometer", tint: .purple),
            WatchMetricItem(title: "걸음수", value: formattedStepCount, unit: "걸음", icon: "shoeprints.fill", tint: .pink),
            WatchMetricItem(title: "칼로리", value: formattedCalories, unit: "kcal", icon: "flame.fill", tint: .red)
        ]
    }

    /// 데이터 화면 — 하나의 화면을 스크롤하며 모든 지표를 봅니다.
    private var metricsPage: some View {
        GeometryReader { geometry in
            let layout = WatchScreenLayout(size: geometry.size)
            // 시스템 시계는 safe area 전체를 확보하되, ScrollView 기본 여백보다만 조금 타이트하게.
            let contentTopPadding = max(geometry.safeAreaInsets.top * 0.78, 16 * layout.scale)

            ScrollView {
                VStack(spacing: layout.gridSpacing) {
                    topBar(layout: layout)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(metricItems, id: \.title) { item in
                        WatchStatCard(item: item, layout: layout)
                            .frame(height: layout.statCardHeight)
                    }
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, contentTopPadding)
                .padding(.bottom, 2)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
    }

    /// 좌: 상태 · 우: 경과 시간 (iPhone StatCard 시계 스타일).
    private func topBar(layout: WatchScreenLayout) -> some View {
        HStack(alignment: .center) {
            Text(statusLabel)
                .font(.system(size: layout.statusFontSize, weight: .bold))
                .foregroundStyle(stateColor)
                .padding(.horizontal, 5 * layout.scale)
                .padding(.vertical, 1)
                .background(stateColor.opacity(0.18), in: Capsule())

            Spacer(minLength: 0)

            HStack(spacing: 3 * layout.scale) {
                Image(systemName: "clock.fill")
                    .font(.system(size: layout.statIconFontSize, weight: .semibold))
                    .foregroundStyle(.blue)

                TimelineView(.periodic(from: .now, by: timerRefreshInterval)) { context in
                    Text(formatElapsedTime(workout.displayedElapsedSeconds(at: context.date)))
                        .font(.system(size: layout.elapsedFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, layout.cardPaddingH)
    }

    private var heartRateValueText: String {
        if let bpm = workout.sessionData.currentHeartRate {
            return "\(Int(bpm.rounded()))"
        }
        return "0"
    }

    private var heartRateValueColor: Color {
        workout.sessionData.currentHeartRate != nil ? .white : .secondary
    }

    // MARK: - 컨트롤 (좌측 스와이프)

    /// 대기 상태 — 가로 바 대신 화면에 맞춰 커지는 원형 시작 버튼.
    private var circularStartButton: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height) * 0.86
            Button {
                WatchHaptics.start()
                LocationPermissionHandling.handleWorkoutStartTap(
                    workout: workout,
                    alert: &locationPermissionAlert,
                    pendingStartWorkout: &pendingStartWorkout
                )
            } label: {
                VStack(spacing: diameter * 0.05) {
                    Image(systemName: "play.fill")
                        .font(.system(size: diameter * 0.34, weight: .bold))
                    Text("시작")
                        .font(.system(size: diameter * 0.16, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
                .background(
                    Circle()
                        .fill(Color.green)
                        .shadow(color: .green.opacity(0.5), radius: diameter * 0.06)
                )
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var controlsPage: some View {
        VStack(spacing: 10) {
            Text("등산 기록")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            iPhoneConnectionBadge()

            if workout.sessionData.state == .idle {
                circularStartButton
            } else {
                if workout.sessionData.state == .recording {
                    WatchActionButton(
                        title: "일시정지",
                        systemImage: "pause.fill",
                        role: .secondary
                    ) {
                        workout.pauseWorkout()
                    }
                } else if workout.sessionData.state == .paused {
                    WatchActionButton(
                        title: "재개",
                        systemImage: "play.fill",
                        role: .primary
                    ) {
                        workout.resumeWorkout()
                    }
                }

                WatchActionButton(
                    title: "종료",
                    systemImage: "stop.fill",
                    role: .destructive
                ) {
                    showEndConfirmation = true
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 6)
        // confirmationDialog는 watchOS에서 버튼이 화면 맨 아래에 깔려 alert로 대체.
        .alert("기록을 종료할까요?", isPresented: $showEndConfirmation) {
            Button("종료", role: .destructive) {
                WatchHaptics.click()
                workout.endWorkout()
            }
            Button("취소", role: .cancel) {
                WatchHaptics.click()
            }
        }
    }

    // MARK: - Formatting

    /// 대기 중에는 컨트롤(시작) 화면, 기록·일시정지 중에는 데이터 화면을 메인으로 둡니다.
    private func preferredTab(for state: HikingSessionState) -> Int {
        state == .idle
            ? WatchWorkoutTab.controls.rawValue
            : WatchWorkoutTab.metrics.rawValue
    }

    private var statusLabel: String {
        switch workout.sessionData.state {
        case .idle: "대기"
        case .recording: "기록 중"
        case .paused: "일시정지"
        }
    }

    private var stateColor: Color {
        switch workout.sessionData.state {
        case .idle: .gray
        case .recording: .green
        case .paused: .orange
        }
    }

    private func formatElapsedTime(_ elapsed: TimeInterval) -> String {
        let total = Int(elapsed.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var formattedDistance: String {
        String(format: "%.2f", workout.sessionData.totalDistance / 1_000)
    }

    private var formattedAltitude: String {
        guard workout.sessionData.state != .idle || !workout.sessionData.points.isEmpty else { return "0" }
        return String(format: "%.0f", workout.sessionData.currentAltitude)
    }

    private var formattedElevationGain: String {
        guard workout.sessionData.state != .idle || !workout.sessionData.points.isEmpty else { return "0" }
        return String(format: "%.0f", workout.sessionData.cumulativeElevationGain)
    }

    private var formattedPace: String {
        guard let pace = workout.sessionData.currentPace else { return "0'00\"" }
        let minutes = Int(pace)
        let seconds = Int((pace - Double(minutes)) * 60)
        return String(format: "%d'%02d\"", minutes, seconds)
    }

    private var formattedStepCount: String {
        let steps = workout.sessionData.stepCount ?? 0
        return NumberFormatter.localizedString(from: NSNumber(value: steps), number: .decimal)
    }

    private var formattedCalories: String {
        let kilocalories = Int((workout.sessionData.activeEnergyKilocalories ?? 0).rounded())
        return NumberFormatter.localizedString(from: NSNumber(value: kilocalories), number: .decimal)
    }
}

// MARK: - Components

private struct iPhoneConnectionBadge: View {
    @EnvironmentObject private var workout: WorkoutManager

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .font(.caption2.weight(.semibold))
            Text(statusText)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("iPhone \(statusText)")
    }

    private var iconName: String {
        guard workout.isWatchConnectivitySupported else { return "iphone.slash" }
        if !workout.isWatchCounterpartInstalled { return "iphone.slash" }
        if workout.isWatchReachable { return "iphone.radiowaves.left.and.right" }
        if workout.isWatchLinkEstablished { return "iphone" }
        return "iphone.slash"
    }

    private var statusText: String {
        guard workout.isWatchConnectivitySupported else { return "미지원" }
        if !workout.isWatchCounterpartInstalled { return "iPhone 미연결" }
        if workout.isWatchReachable { return "iPhone 연결됨" }
        if workout.isWatchLinkEstablished { return "iPhone 연결됨" }
        return "iPhone 확인 중"
    }

    private var statusColor: Color {
        guard workout.isWatchConnectivitySupported else { return .secondary }
        if !workout.isWatchCounterpartInstalled { return .secondary }
        if workout.isWatchLinkEstablished { return .green }
        return .orange
    }
}

private struct WatchMetricItem {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let tint: Color
    var valueColor: Color = .white
}

/// 아이콘·라벨 한 줄 + 값 — 모든 데이터 값이 동일한 숫자 폰트(`statValueFontSize`)를 씁니다.
private struct WatchStatCard: View {
    let item: WatchMetricItem
    let layout: WatchScreenLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 1 * layout.scale) {
            HStack(spacing: 3 * layout.scale) {
                Image(systemName: item.icon)
                    .font(.system(size: layout.statIconFontSize, weight: .semibold))
                    .foregroundStyle(item.tint)

                Text(item.title)
                    .font(.system(size: layout.secondaryLabelFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Spacer(minLength: 0)
                Text(item.value)
                    .font(.system(size: layout.statValueFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(item.valueColor)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                if !item.unit.isEmpty {
                    Text(item.unit)
                        .font(.system(size: layout.secondaryUnitFontSize, weight: .semibold))
                        .foregroundStyle(item.tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(.horizontal, layout.cardPaddingH)
        .padding(.vertical, layout.cardPaddingV)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous))
    }
}

private struct WatchActionButton: View {
    enum Role {
        case primary, secondary, destructive
    }

    let title: String
    let systemImage: String
    let role: Role
    let action: () -> Void

    var body: some View {
        Button {
            tapHaptic()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .tint(tintColor)
    }

    private func tapHaptic() {
        switch role {
        case .primary: WatchHaptics.start()
        case .secondary: WatchHaptics.tap()
        case .destructive: WatchHaptics.tap()
        }
    }

    private var tintColor: Color {
        switch role {
        case .primary: .green
        case .secondary: .orange
        case .destructive: .red
        }
    }
}

// MARK: - 종료 요약

/// 종료 후 저장 전 종합 데이터 검토 — 저장/삭제 선택.
private struct WatchWorkoutSummaryView: View {
    let session: HikingSessionData
    let onSave: () -> Void
    let onDiscard: () -> Void

    @State private var showDiscardConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("기록 요약")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    SummaryCell(title: "시간", value: formattedDuration, unit: "")
                    SummaryCell(title: "거리", value: formattedDistance, unit: "km")
                    SummaryCell(title: "상승", value: formattedElevationGain, unit: "m")
                    SummaryCell(title: "평균속도", value: formattedPace, unit: "")
                    SummaryCell(title: "걸음수", value: formattedStepCount(session.stepCount ?? 0), unit: "걸음")
                    SummaryCell(title: "칼로리", value: formattedCalories(session.activeEnergyKilocalories ?? 0), unit: "kcal")
                }

                Text("GPS \(session.points.count)개 포인트")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                Button {
                    WatchHaptics.success()
                    onSave()
                } label: {
                    Label("저장 완료", systemImage: "checkmark")
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button(role: .destructive) {
                    WatchHaptics.click()
                    showDiscardConfirmation = true
                } label: {
                    Label("삭제", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.horizontal, 4)
        }
        .interactiveDismissDisabled(true)
        .alert("이 기록을 삭제할까요?", isPresented: $showDiscardConfirmation) {
            Button("삭제", role: .destructive) {
                WatchHaptics.click()
                onDiscard()
            }
            Button("취소", role: .cancel) {
                WatchHaptics.click()
            }
        } message: {
            Text("저장하지 않고 폐기합니다.")
        }
    }

    private var formattedDuration: String {
        let total = Int(session.elapsedTime.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var formattedDistance: String {
        String(format: "%.2f", session.totalDistance / 1_000)
    }

    private var formattedElevationGain: String {
        String(format: "%.0f", session.elevationGainMeters ?? session.cumulativeElevationGain)
    }

    private var formattedPace: String {
        let seconds = session.elapsedTime
        let kilometers = session.totalDistance / 1_000
        guard seconds > 0, kilometers >= 0.01 else { return "0'00\"" }
        let pace = (seconds / 60) / kilometers
        let minutes = Int(pace)
        let secs = Int((pace - Double(minutes)) * 60)
        return String(format: "%d'%02d\"", minutes, secs)
    }

    private func formattedStepCount(_ steps: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: steps), number: .decimal)
    }

    private func formattedCalories(_ kilocalories: Double) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: Int(kilocalories.rounded())), number: .decimal)
    }
}

private struct SummaryCell: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private enum WatchWorkoutTab: Int {
    case metrics = 0
    case controls = 1
}

private struct WatchResumeHikingPromptModifier: ViewModifier {
    @ObservedObject var workout: WorkoutManager

    private var isPresented: Binding<Bool> {
        Binding(
            get: { workout.resumeHikingPrompt != nil },
            set: { isPresented in
                if !isPresented {
                    workout.dismissResumeHikingPrompt()
                }
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: workout.resumeHikingPrompt) { _, newValue in
                if newValue != nil {
                    WatchHaptics.notification()
                }
            }
            .alert("산행이 감지됐어요", isPresented: isPresented) {
                Button("기록 재개") {
                    WatchHaptics.start()
                    workout.confirmResumeHikingPrompt()
                }
                Button("계속 일시정지", role: .cancel) {
                    WatchHaptics.click()
                    workout.dismissResumeHikingPrompt()
                }
            } message: {
                Text("일시정지 중 이동이 감지됐어요. 기록을 이어갈까요?")
            }
    }
}

private extension View {
    func watchResumeHikingPromptAlert(workout: WorkoutManager) -> some View {
        modifier(WatchResumeHikingPromptModifier(workout: workout))
    }
}

#Preview {
    WatchWorkoutView()
        .environmentObject(WorkoutManager.shared)
}
