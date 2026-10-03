//
//  WorkoutManager.swift
//  Shared
//
//  등산 워크아웃 오케스트레이터 (iPhone · Watch 공통 싱글톤).
//  Xcode: Shared/Workout 타겟 멤버십 → sansan, sansan Watch App
//

import Combine
import CoreLocation
import Foundation
import HealthKit
import os
import WatchConnectivity
#if os(iOS)
import UIKit
#endif

/// 일시정지 중 산행 이동이 감지됐을 때 기록 재개 확인용.
struct ResumeHikingPrompt: Equatable {
    let netDisplacementMeters: Double
    let stepsSincePause: Int
}

/// GPS 수집·메트릭 계산·기기 간 세션 동기화를 담당하는 싱글톤 매니저.
@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    static let shared = WorkoutManager()

    /// 실기기 진단용 — Console.app/Xcode 콘솔에서 `category:WorkoutManager`로 필터링합니다.
    nonisolated static let diagnosticLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.jw.sansan",
        category: "WorkoutManager"
    )

    @Published private(set) var sessionData = HikingSessionData()
    @Published private(set) var isWatchReachable = false
    @Published private(set) var isWatchConnectivitySupported = false
    /// iPhone: Watch 앱 설치 여부 / Watch: iPhone 컴패니언 앱 설치 여부.
    @Published private(set) var isWatchCounterpartInstalled = false
    /// WCSession 활성화 + 상대 앱 설치가 확인된 상태 (`isReachable`과 별개).
    @Published private(set) var isWatchLinkEstablished = false
    /// 최근 WatchConnectivity 동기화 시각 — reachable이 잠깐 false여도 UI·폴백 판단에 사용.
    @Published private(set) var lastWatchSyncAt: Date?
#if os(iOS)
    /// 워치 연결이 끊겨 iPhone이 위치 기록을 이어받은 상태.
    @Published private(set) var isPhoneRecordingFailoverActive = false
#endif
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
#if os(iOS)
    /// 메인 지도용 최근 위치(기록 대기 중).
    @Published private(set) var lastKnownMapLocation: CLLocation?
#endif
    /// 기록 종료 후 저장 목록 화면 표시 요청(iPhone).
    @Published private(set) var shouldPresentRecordsList = false
    /// 기록 시작 전 카운트다운 남은 초 — 표시 중에는 GPS·심박 센서를 워밍업합니다.
    @Published private(set) var startCountdownRemaining: Int?
    /// 종료 버튼 후 저장 전 검토용 세션 — nil이 아니면 요약 화면을 띄웁니다.
    @Published private(set) var summarySession: HikingSessionData?
    /// 일시정지 중 방향성 이동 감지 시 기록 재개 확인.
    @Published private(set) var resumeHikingPrompt: ResumeHikingPrompt?

#if os(iOS)
    /// iPhone 앱에서 등록 — `HikingRecordStore`는 iOS 전용 타입이라 Shared에서 직접 참조하지 않습니다.
    static var sessionArchiveHandler: (@MainActor (HikingSessionData) -> Void)?
#endif

    private let locationManager = CLLocationManager()
    private var wcSession: WCSession?

    /// 기록 구간 걸음수 수집기(Core Motion) — 기록을 수행하는 기기에서만 동작합니다.
    private let stepCounter = StepCounter()
    /// 일시정지 중 산행 이동 감지용 만보계(기록에는 반영하지 않음).
    private let pauseActivityStepCounter = StepCounter()
    private var pauseActivityMonitorActive = false
    private var pauseActivityOrigin: CLLocationCoordinate2D?
    private var pauseActivityLocations: [CLLocation] = []
    private var pauseActivityStepCount = 0
    private var resumeHikingPromptSuppressedUntil: Date?

    private var workoutStartDate: Date?
    private var accumulatedPausedTime: TimeInterval = 0
    private var pauseBeganAt: Date?
    private var elapsedTimerTask: Task<Void, Never>?
    private var startCountdownTask: Task<Void, Never>?
    private var isApplyingRemoteUpdate = false
    /// 종료 후 요약 검토 중 — 원격 갱신·타이머가 기록을 다시 켜지 않도록 합니다.
    private var isAwaitingSummaryConfirmation = false
    private var isLocationProducer = true
    /// 마지막으로 누적 거리에 반영한 포인트 — 2m 미만 GPS 흔들림은 anchor 기준으로 걸러냅니다.
    private var liveDistanceAnchor: HikingPoint?
    /// 재개 직후 첫 GPS 포인트를 받아 현재 일시정지 마킹의 재개 좌표를 채우기 위한 플래그.
    private var awaitingResumeMarker = false
    /// 기록 중 세션 로컬 백업 최근 저장 시각(스로틀용).
    private var lastLiveBackupSavedAt: Date?
    /// 로컬에서 종료한 세션 — 상대 기기의 기록 중 스냅샷이 타이머를 다시 켜지 않도록 합니다.
    private var dismissedSessionID: UUID?
    private static let dismissedSessionIDDefaultsKey = "sansan.workout.dismissedSessionID"
    /// 오래된 캐시 스냅샷이 앱 시작 직후 기록을 복원하지 않도록 합니다.
    private static let staleRemoteSessionMaxAge: TimeInterval = 3_600
    /// idle iPhone이 Watch 캐시만으로 기록 UI를 켤 수 있는 최대 스냅샷 나이(초).
    private static let idleRemoteAdoptionMaxAge: TimeInterval = 90
    /// reachable이 false여도 최근 동기화가 있으면 링크가 살아 있다고 봅니다.
    private static let watchSyncActivityGrace: TimeInterval = 45
    /// 워치가 이 시간 동안 비활성이면 iPhone이 위치 기록을 이어받습니다(초).
    private static let watchLossFailoverThreshold: TimeInterval = 45
    private var watchConnectivityRetryTask: Task<Void, Never>?
#if os(iOS)
    private var didPrepareAfterMainScreen = false
#endif

    #if os(iOS)
    private var backgroundActivitySession: CLBackgroundActivitySession?
    private var photoLocationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var isAwaitingPhotoLocation = false
    /// Apple Watch 운동 앱 실행용 HealthKit 스토어(재사용).
    private var watchWorkoutLauncherHealthStore: HKHealthStore?
    /// 워치 운동 앱 실행 요청 진행 중 — 중복 실행을 막습니다.
    private var isLaunchingWatchWorkout = false
    private var isMapLocationTrackingActive = false
    private let routeTrackingAccuracy = kCLLocationAccuracyBest
    private let mapLocationDistanceFilter: CLLocationDistance = 25
    /// iPhone: 기록 중 화면 꺼짐·백그라운드 종료 방지용 HKWorkoutSession.
    private var iPhoneWorkoutKeepAlive: PhoneWorkoutKeepAliveSession?
    /// GPS 품질 저하로 워치에 GPS 보조 수집을 요청한 상태.
    private var isWatchLocationAssistActive = false
    /// 마지막으로 로컬 GPS 포인트를 채택한 시각(품질 저하 판단용).
    private var lastAcceptedLocalPointAt: Date?
    /// 원시 GPS 정확도가 나쁜 상태가 시작된 시각(지속 시간 판단용).
    private var poorAccuracyStreakStartedAt: Date?
    /// 채택 포인트 정확도가 양호한 상태가 시작된 시각(회복 판단용).
    private var goodAccuracyStreakStartedAt: Date?
    /// 워치 비활성 감지가 시작된 시각 — 짧은 BLE 끊김은 넘깁니다.
    private var watchConnectivityLossStartedAt: Date?
    /// iPhone이 워치 대신 기록을 이어받은 시각. 이후 워치 GPS는 병합하지 않습니다.
    private var phoneRecordingFailoverAt: Date?
    /// 워치가 다시 켜졌을 때 인계 명령을 다시 보내기 위한 플래그.
    private var didNotifyWatchOfPhoneTakeover = false
    private var watchLossFailoverTask: Task<Void, Never>?
#endif

    #if os(watchOS)
    /// 기록 중 손목 내림·화면 꺼짐 후에도 앱이 유지되도록 하는 HKWorkoutSession.
    private var watchWorkoutSession: WatchHeartRateWorkoutSession?
    private var lastHeartRateSnapshotPublishedAt: Date?
    private var lastElapsedSnapshotPublishedAt: Date?
    /// 손목을 내렸을 때(`isLuminanceReduced`) UI·동기화 빈도를 줄입니다.
    private var isWatchDisplayLuminanceReduced = false
    /// iPhone GPS 품질 저하로 임시 GPS 보조 수집 중.
    private var isAssistingLocation = false
    /// 보조 수집 포인트 버퍼 — 원격 스냅샷 병합과 분리해 두고 보조 중단·종료 시 세션에 합칩니다.
    private var assistPoints: [HikingPoint] = []
    /// HKWorkoutSession 시작 실패 시 재시도 횟수(세션이 `.running`에 도달하면 초기화).
    private var watchWorkoutSessionRestartAttempts = 0
    private static let maxWatchWorkoutSessionRestartAttempts = 3
    #endif

    /// Watch → iPhone 심박 스냅샷 전송 간격(초). Apple Watch 심박 갱신(~5초)에 맞춥니다.
    private static let heartRateSnapshotMinInterval: TimeInterval = 1
    private static let publishedHeartRateSampleLimit = 60
    /// GPX 트랙과 비슷하게 모든 GPS 갱신을 받습니다.
    private static let routeTrackingDistanceFilter: CLLocationDistance = kCLDistanceFilterNone
    /// GPX보내기 앱과 비슷한 약 1초 간격으로 포인트를 저장합니다.
    private static let recordingPointMinInterval: TimeInterval = 1
    /// 1초 안에 거의 움직이지 않았으면 정지 상태 GPS 흔들림 포인트를 건너뜁니다.
    /// 경로를 촘촘히 남기되 제자리 미세 흔들림만 거르는 최소 변위(m).
    /// 휴식·정상 체류 등 장시간 정지 시 GPS 드리프트(±수 m)가 경로로 누적돼 엉키는 것을 막기 위해
    /// 소비자 GPS 노이즈 바닥(약 3m)으로 올립니다.
    private static let recordingPointMinDistance: CLLocationDistance = 3
    /// 이보다 수평 정확도가 나쁜 GPS 픽스는 저장하지 않습니다(실내·다중경로 노이즈 차단).
    private static let maxStorableHorizontalAccuracy: CLLocationDistance = 30
    /// 일정 시간 포인트가 없으면(긴 공백) 도심 협곡 등에서 정확도가 다소 나빠도 경로 연속성을 위해 저장합니다.
    private static let maxStorableHorizontalAccuracyDuringGap: CLLocationDistance = 65
    /// 이 시간 이상 채택 포인트가 없으면 완화된 정확도 게이트를 적용합니다(초).
    private static let recordingGapRescueInterval: TimeInterval = 8
    /// 정확도 비례 저장 임계 계수 — 정확도가 나쁠수록(나무 아래·협곡) 더 큰 변위에서만 저장해
    /// 드리프트가 경로로 쌓이는 것을 막습니다.
    private static let recordingPointAccuracyFactor: Double = 0.4
    /// 정확도 비례 저장 임계 상한(m) — 정확도가 나빠도 실제 이동은 기록되도록 합니다.
    private static let recordingPointMaxThreshold: CLLocationDistance = 10
    /// `transferUserInfo` 페이로드 한도(약 65KB)를 넘지 않을 포인트 수.
    /// 이보다 큰 세션은 `transferFile`(크기 제한 없음)로 전체를 전송합니다.
    private static let maxUserInfoTransferPointCount = 200
    /// `transferUserInfo` 페이로드에 포함할 최대 심박 샘플 수.
    private static let maxUserInfoTransferHeartRateSampleCount = 120
    /// 시작 카운트다운 길이(초) — GPS 첫 픽스·심박 센서 워밍업 시간을 확보합니다.
    private static let startCountdownSeconds = 3
    /// 기록 중 세션 로컬 백업 최소 저장 간격(초).
    private static let liveBackupMinInterval: TimeInterval = 15
    /// 백업이 이보다 오래됐으면 기록 재개 대신 완료된 기록으로 저장합니다.
    private static let liveBackupMaxResumeAge: TimeInterval = 1_800
    /// 일시정지 후 재개 확인 — 최소 대기(초).
    private static let resumePromptMinPauseDuration: TimeInterval = 45
    /// 일시정지 지점 대비 순이동 거리(미터).
    private static let resumePromptMinNetDisplacement: CLLocationDistance = 35
    /// 일시정지 후 최소 걸음 수.
    private static let resumePromptMinSteps = 28
    /// 순이동 / 이동경로 — 방향성 걸음(왕복·제자리 흔들림 제외).
    private static let resumePromptMinDirectionality = 0.48
    /// 재개 확인을 무시한 뒤 다시 묻지 않는 시간(초).
    private static let resumePromptCooldown: TimeInterval = 480
#if os(iOS)
    /// 이 시간 이상 채택 포인트가 없으면 GPS 품질 저하로 보고 워치 보조를 요청합니다(초).
    private static let assistNoAcceptedPointInterval: TimeInterval = 20
    /// 원시 GPS 정확도가 이보다 나쁜 상태가 지속되면 품질 저하로 봅니다(m).
    private static let assistDegradedAccuracy: CLLocationDistance = 45
    /// 나쁜 정확도 지속 판정 시간(초).
    private static let assistDegradedSustainInterval: TimeInterval = 15
    /// 회복 판정 — 채택 포인트 정확도 한도(m).
    private static let assistRecoveredAccuracy: CLLocationDistance = 30
    /// 양호한 정확도 지속 판정 시간(초).
    private static let assistRecoverySustainInterval: TimeInterval = 10
#endif
#if os(watchOS)
    /// 워치 GPS 보조 수집 포인트의 수평 정확도 한도(m).
    private static let assistMaxHorizontalAccuracy: CLLocationDistance = 50
#endif
    private static let pauseActivityMaxSamples = 24
    private static let pauseActivityMinSampleSpacing: CLLocationDistance = 8
    private static let pauseActivityMaxHorizontalAccuracy: CLLocationDistance = 40
    private static let pauseActivityLocationDistanceFilter: CLLocationDistance = 14

    override private init() {
        super.init()
        loadPersistedDismissedSessionID()
        configureLocationManager()
        authorizationStatus = locationManager.authorizationStatus
#if os(watchOS)
        configureWatchConnectivity()
        Task { await self.restoreLiveSessionBackupIfNeeded() }
        Task { await self.prepareHeartRateMonitoringEarlyIfNeeded() }
#endif
    }

#if os(iOS)
    /// 메인 탭이 먼저 살아난 뒤에 WC·백업 복원·심박 준비를 붙입니다.
    func prepareAfterMainScreenReady() async {
        guard !didPrepareAfterMainScreen else { return }
        didPrepareAfterMainScreen = true
        await restoreLiveSessionBackupIfNeeded()
        configureWatchConnectivity()
        Task { await prepareHeartRateMonitoringEarlyIfNeeded() }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            self?.kickWatchConnectivityHandshake()
        }
    }
#endif

    private func prepareHeartRateMonitoringEarlyIfNeeded() async {
#if os(iOS)
        guard HeartRatePreferences.isFeatureEnabled else { return }
        guard HeartRatePreferences.isMonitoringEnabled else { return }
        await HeartRateMonitor.shared.prepareForWorkout()
#else
        await prepareWatchWorkoutRuntime()
#endif
    }

    private func loadPersistedDismissedSessionID() {
        guard
            let raw = UserDefaults.standard.string(forKey: Self.dismissedSessionIDDefaultsKey),
            let sessionID = UUID(uuidString: raw)
        else { return }
        dismissedSessionID = sessionID
    }

    private func persistDismissedSessionID(_ sessionID: UUID?) {
        dismissedSessionID = sessionID
        if let sessionID {
            UserDefaults.standard.set(sessionID.uuidString, forKey: Self.dismissedSessionIDDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.dismissedSessionIDDefaultsKey)
        }
    }

    // MARK: - Public controls

    func startWorkout() {
#if os(iOS)
        Task { await prepareAfterMainScreenReady() }
#endif
        guard sessionData.state != .recording else { return }
        if sessionData.state == .paused {
            beginWorkout(syncRemote: true, asLocationProducer: true)
            return
        }
        guard startCountdownTask == nil else { return }

        // 카운트다운 동안 GPS 첫 픽스·심박 센서를 미리 준비해 시작 직후 데이터 공백을 줄입니다.
        warmUpSensorsForStart()
        updateScreenSleepPrevention()
        startCountdownTask = Task { @MainActor [weak self] in
            var remaining = Self.startCountdownSeconds
            while remaining > 0 {
                guard let self, !Task.isCancelled else { return }
                self.startCountdownRemaining = remaining
                try? await Task.sleep(for: .seconds(1))
                remaining -= 1
            }
            guard let self, !Task.isCancelled else { return }
            self.startCountdownRemaining = nil
            self.startCountdownTask = nil
            self.beginWorkout(syncRemote: true, asLocationProducer: true)
        }
    }

    /// 카운트다운 중 취소 — 워밍업으로 켠 GPS를 원래 상태로 되돌립니다.
    func cancelStartCountdown() {
        startCountdownTask?.cancel()
        startCountdownTask = nil
        startCountdownRemaining = nil
        updateScreenSleepPrevention()
        guard sessionData.state == .idle else { return }
        locationManager.stopUpdatingLocation()
#if os(watchOS)
        disableWatchBackgroundLocation()
#endif
#if os(iOS)
        prepareDashboardMapLocation()
#endif
    }

    private func warmUpSensorsForStart() {
        if canRecordWithCurrentLocationAuthorization {
#if os(watchOS)
            disableWatchBackgroundLocation()
#endif
            applyRecordingLocationConfiguration()
            locationManager.startUpdatingLocation()
        }
        prepareHeartRateMonitoringForWorkout()
    }

    func pauseWorkout() {
        guard sessionData.state == .recording else { return }
        setPaused(syncRemote: true)
    }

    func resumeWorkout() {
        guard sessionData.state == .paused else { return }
        setResumed(syncRemote: true)
    }

    /// 일시정지 중 산행 이동 알림 — 계속 일시정지.
    func dismissResumeHikingPrompt() {
        resumeHikingPrompt = nil
        resumeHikingPromptSuppressedUntil = Date().addingTimeInterval(Self.resumePromptCooldown)
    }

    /// 일시정지 중 산행 이동 알림 — 기록 재개.
    func confirmResumeHikingPrompt() {
        resumeHikingPrompt = nil
        resumeHikingPromptSuppressedUntil = nil
        resumeWorkout()
    }

    func endWorkout() {
        guard sessionData.state == .recording || sessionData.state == .paused else { return }

        finalizeSessionBeforeEnd()
        postProcessTrackForEnd()
        stopWorkoutTracking()
        finalizeActiveEnergyEstimateIfNeeded()
        isAwaitingSummaryConfirmation = true

        var finished = sessionData
        finished.state = .idle
        finished.finalizeForPersistence()
        summarySession = finished

        // UI·동기화는 idle, 검토 데이터는 summarySession·백업에만 보관합니다.
        sessionData = HikingSessionData()
        saveSummaryPendingBackup(finished)

        finalizeStepCount()
    }

    /// 요약 화면의 "완료" — 기록을 저장하고 상대 기기로 전송한 뒤 초기화합니다.
    func confirmSummary() {
        guard let finished = summarySession else { return }
        isAwaitingSummaryConfirmation = false
        summarySession = nil

        persistDismissedSessionID(finished.sessionID)
        archiveFinishedSession(finished, presentList: false)

        if !isApplyingRemoteUpdate {
            broadcastEndSession(finished)
        }
        publishSessionEndedMarker(for: finished.sessionID)

        resetSessionToIdle()
    }

    /// 요약 화면의 "삭제" — 저장하지 않고 폐기합니다(상대 기기에도 폐기 전달).
    func discardSummary() {
        guard let finished = summarySession else { return }
        isAwaitingSummaryConfirmation = false
        summarySession = nil

        persistDismissedSessionID(finished.sessionID)
        broadcastDiscard()
        resetSessionToIdle()
    }

    func clearPendingRecordsPresentation() {
        shouldPresentRecordsList = false
    }

#if os(iOS)
    /// Watch에서 받은 완료 세션이 라이브 기록으로 되살아나지 않게 하고, 상대 기기에 수신을 알립니다.
    func acknowledgeWatchInboundSession(_ sessionID: UUID) {
        persistDismissedSessionID(sessionID)
        publishSessionEndedMarker(for: sessionID)
    }
#endif

#if os(watchOS)
    /// Watch UI — 손목 내림(Always On 저휘도) 상태를 WorkoutManager에 전달합니다.
    func setWatchDisplayLuminanceReduced(_ reduced: Bool) {
        isWatchDisplayLuminanceReduced = reduced
    }

    /// 앱이 다시 열릴 때 기록 중이면 HKWorkoutSession·타이머를 재연결하고 WC 상태를 갱신합니다.
    func syncWatchRuntimeOnAppear() {
        syncLocalTrackingToState()
        kickWatchConnectivityHandshake()
    }

    /// 기록 시작 전 HealthKit 권한을 미리 요청합니다.
    func prepareWatchWorkoutRuntime() async {
        await WatchHeartRateWorkoutSession.prepareAuthorizationIfNeeded()
    }

    /// Watch 타이머 UI — 주어진 시각 기준 경과 시간(초).
    func displayedElapsedSeconds(at date: Date = Date()) -> TimeInterval {
        switch sessionData.state {
        case .idle:
            return 0
        case .paused:
            return sessionData.elapsedTime
        case .recording:
            guard let startDate = workoutStartDate ?? sessionData.effectiveStartedAt else {
                return sessionData.elapsedTime
            }
            return max(0, date.timeIntervalSince(startDate) - accumulatedPausedTime)
        }
    }
#endif

#if os(iOS)
    /// Apple Watch가 연결돼 있으면 기록 시작 시 심박 측정을 자동으로 켭니다.
    private func enableHeartRateMonitoringIfWatchAvailable() {
        guard isWatchCounterpartInstalled else { return }
        guard HeartRatePreferences.isFeatureEnabled else { return }
        if !HeartRatePreferences.isMonitoringEnabled {
            HeartRatePreferencesObserver.shared.setMonitoringEnabled(true)
        }
    }

    private var shouldCollectHeartRateDuringWorkout: Bool {
        guard HeartRatePreferences.isFeatureEnabled else { return false }
        if isWatchCounterpartInstalled { return true }
        return HeartRatePreferences.isMonitoringEnabled
    }
#endif

#if os(iOS)
    /// 일반설정 — 심박수 기능 on/off.
    func setHeartRateFeatureEnabled(_ isEnabled: Bool) async {
        HeartRatePreferencesObserver.shared.setFeatureEnabled(isEnabled)
        if isEnabled {
            if HeartRatePreferences.isMonitoringEnabled, HeartRateMonitor.canUseHealthKit {
                try? await HeartRateMonitor.shared.requestAuthorization()
                startHeartRateCollectionIfNeeded()
            }
        } else {
            HeartRatePreferencesObserver.shared.setMonitoringEnabled(false)
            stopHeartRateCollection()
        }
    }

    /// 메인 심박수 카드 — 측정 on/off.
    func setHeartRateMonitoringEnabled(_ isEnabled: Bool) async {
        guard HeartRatePreferences.isFeatureEnabled else { return }
        HeartRatePreferencesObserver.shared.setMonitoringEnabled(isEnabled)
        if isEnabled {
            guard HeartRateMonitor.canUseHealthKit else { return }
            try? await HeartRateMonitor.shared.requestAuthorization()
            startHeartRateCollectionIfNeeded()
        } else {
            stopHeartRateCollection()
        }
    }
#endif

#if os(iOS)
    /// 앱 기동·포그라운드 복귀 시 WatchConnectivity를 깨우고 큐에 쌓인 종료 세션 전달을 받습니다.
    func syncPendingWatchSessions() {
        guard didPrepareAfterMainScreen else { return }
        kickWatchConnectivityHandshake()
    }
#endif

    /// WCSession 상태를 즉시 읽고, 필요하면 활성화합니다.
    func refreshWatchConnectivity() {
        guard WCSession.isSupported() else {
            isWatchConnectivitySupported = false
            isWatchCounterpartInstalled = false
            isWatchLinkEstablished = false
            isWatchReachable = false
            return
        }

        let session = wcSession ?? WCSession.default
        if wcSession == nil {
            wcSession = session
            isWatchConnectivitySupported = true
            session.delegate = self
        }

        if session.activationState != .activated {
            session.activate()
        }
        refreshWatchCounterpartState(session)
    }

    /// 포그라운드 진입·화면 표시 직후 reachability가 늦게 true가 되는 경우를 대비해 재확인합니다.
    func kickWatchConnectivityHandshake() {
        refreshWatchConnectivity()

        watchConnectivityRetryTask?.cancel()
        watchConnectivityRetryTask = Task { @MainActor [weak self] in
            let delays: [Duration] = [
                .milliseconds(350),
                .milliseconds(900),
                .seconds(2),
                .seconds(4)
            ]
            for delay in delays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                self.refreshWatchConnectivity()
                if self.isWatchReachable {
                    self.requestSessionSyncFromCounterpart()
                }
                if self.isWatchLinkEstablished, self.isWatchReachable {
                    return
                }
            }
        }
    }

    /// UI·폴백용 — 실시간 reachable이거나 최근 동기화가 있으면 활성 링크.
    var isWatchActivelyLinked: Bool {
        guard isWatchLinkEstablished else { return false }
        if isWatchReachable { return true }
        guard let lastWatchSyncAt else { return false }
        return Date().timeIntervalSince(lastWatchSyncAt) < Self.watchSyncActivityGrace
    }

    private func markWatchSyncActivity() {
        lastWatchSyncAt = Date()
    }

#if os(iOS)
    /// 기록 중 사진을 고정밀 GPS 위치에 연결해 저장합니다.
    @discardableResult
    func addTrailPhoto(_ image: UIImage) async -> Bool {
        guard sessionData.state == .recording || sessionData.state == .paused else { return false }
        guard let location = await resolvePhotoCaptureLocation() else { return false }

        let photoID = UUID()
        let filename = HikingStorageLayout.photoFilename(photoID: photoID)
        do {
            try HikingTrailPhotoStore.saveJPEG(image, sessionID: sessionData.sessionID, filename: filename)
        } catch {
            return false
        }

        let photo = HikingTrailPhoto(
            id: photoID,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            filename: filename
        )
        sessionData.photos.append(photo)
        sessionData.lastUpdated = Date()
        publishSessionSnapshot()
        return true
    }

    private func resolvePhotoCaptureLocation() async -> CLLocation? {
        if let fresh = freshLocationForPhotoCapture() {
            return fresh
        }
        if let requested = await requestHighAccuracyPhotoLocation() {
            return requested
        }
        if let routeMatch = nearestRouteLocation(to: Date()) {
            return routeMatch
        }
        if let last = sessionData.points.last {
            return CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: last.latitude, longitude: last.longitude),
                altitude: last.altitude,
                horizontalAccuracy: 25,
                verticalAccuracy: -1,
                timestamp: last.timestamp
            )
        }
        return nil
    }

    private func freshLocationForPhotoCapture() -> CLLocation? {
        guard let location = locationManager.location else { return nil }
        guard location.horizontalAccuracy > 0, location.horizontalAccuracy <= 20 else { return nil }
        let age = abs(location.timestamp.timeIntervalSinceNow)
        guard age <= 8 else { return nil }
        return location
    }

    private func requestHighAccuracyPhotoLocation() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            photoLocationContinuation = continuation
            isAwaitingPhotoLocation = true
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.requestLocation()

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard let self, self.isAwaitingPhotoLocation else { return }
                self.finishPhotoLocationRequest(returning: nil)
            }
        }
    }

    private func finishPhotoLocationRequest(returning location: CLLocation?) {
        isAwaitingPhotoLocation = false
        restoreRouteTrackingAccuracy()
        photoLocationContinuation?.resume(returning: location)
        photoLocationContinuation = nil
    }

    private func restoreRouteTrackingAccuracy() {
        locationManager.desiredAccuracy = routeTrackingAccuracy
    }

    private func nearestRouteLocation(to date: Date) -> CLLocation? {
        guard let nearest = sessionData.points.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        }) else { return nil }
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: nearest.latitude, longitude: nearest.longitude),
            altitude: nearest.altitude,
            horizontalAccuracy: 15,
            verticalAccuracy: -1,
            timestamp: date
        )
    }
#endif

    var canRecordWithCurrentLocationAuthorization: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    var needsLocationPermissionExplanation: Bool {
        authorizationStatus == .notDetermined
    }

    var isLocationPermissionBlocked: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    /// 최초 위치 권한 — 사용 중 허용만 요청합니다. 안내는 UI에서 먼저 표시합니다.
    func requestWhenInUseLocationAuthorization() {
        guard authorizationStatus == .notDetermined else { return }
        locationManager.requestWhenInUseAuthorization()
    }

#if os(iOS)
    /// 백그라운드 기록용 항상 허용 — 안내 후 UI에서 호출합니다.
    func requestAlwaysLocationAuthorization() {
        guard authorizationStatus == .authorizedWhenInUse else { return }
        locationManager.requestAlwaysAuthorization()
    }
#endif

    /// 위치 권한이 없을 때 UI에서 호출. (When-In-Use만 요청)
    func requestLocationAuthorization() {
        requestWhenInUseLocationAuthorization()
    }

#if os(iOS)
    /// 앱이 포그라운드로 돌아왔을 때 기록 중 위치 추적·대기 중 지도 위치를 다시 보장합니다.
    func refreshLocationTrackingIfNeeded() {
        guard didPrepareAfterMainScreen || sessionData.state == .recording else { return }
        if sessionData.state == .recording {
            restartLocationTrackingForActiveWorkout()
        } else {
            prepareDashboardMapLocation()
        }
    }

    /// 메인 지도 — 권한 요청(최초 1회) 및 대기 중 위치 갱신을 시작합니다.
    func prepareDashboardMapLocation() {
        authorizationStatus = locationManager.authorizationStatus
        guard sessionData.state == .idle else { return }

        if needsLocationPermissionExplanation {
            requestWhenInUseLocationAuthorization()
            return
        }

        guard canRecordWithCurrentLocationAuthorization else { return }
        startMapLocationUpdatesIfNeeded()
    }

    private func startMapLocationUpdatesIfNeeded() {
        guard sessionData.state == .idle else { return }
        guard canRecordWithCurrentLocationAuthorization else { return }

        applyMapLocationConfiguration()
        if let location = locationManager.location {
            lastKnownMapLocation = location
        }

        guard !isMapLocationTrackingActive else { return }
        locationManager.startUpdatingLocation()
        isMapLocationTrackingActive = true
    }

    private func publishMapLocationIfNeeded(_ location: CLLocation) {
        if let last = lastKnownMapLocation,
           location.distance(from: last) < 25,
           location.timestamp.timeIntervalSince(last.timestamp) < 1.5 {
            return
        }
        lastKnownMapLocation = location
    }

    private func stopMapLocationUpdates() {
        isMapLocationTrackingActive = false
        guard sessionData.state == .idle else { return }
        locationManager.stopUpdatingLocation()
    }

    private func applyMapLocationConfiguration() {
        locationManager.activityType = .other
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = mapLocationDistanceFilter
        locationManager.pausesLocationUpdatesAutomatically = true
        disableBackgroundLocation()
    }
#endif

    // MARK: - Location setup

    private func configureLocationManager() {
        locationManager.delegate = self
        locationManager.activityType = .fitness
#if os(iOS)
        locationManager.desiredAccuracy = routeTrackingAccuracy
#else
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
#endif
        locationManager.distanceFilter = Self.routeTrackingDistanceFilter
#if os(iOS) || os(macOS)
        locationManager.pausesLocationUpdatesAutomatically = true
#endif
    }

#if os(iOS)
    /// Info.plist `UIBackgroundModes`에 `location`이 없으면 백그라운드 위치 API 호출 시 즉시 크래시합니다.
    private var supportsBackgroundLocationMode: Bool {
        guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            return false
        }
        return modes.contains("location")
    }

    private var canUseBackgroundLocationTracking: Bool {
        guard supportsBackgroundLocationMode else { return false }
        return authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    /// `allowsBackgroundLocationUpdates`는 UIBackgroundModes(location)이 있으면 When-In-Use 권한으로도
    /// 동작합니다. When-In-Use는 `CLBackgroundActivitySession`이 백그라운드 위치를 유지해 줍니다 —
    /// Always만 허용하면 화면 꺼짐과 동시에 앱이 중단되어 GPS 기록이 끊깁니다.
    private func enableBackgroundLocationIfAuthorized() {
        guard supportsBackgroundLocationMode else { return }
        authorizationStatus = locationManager.authorizationStatus
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        default:
            return
        }
        ensureBackgroundActivitySession()
        if !locationManager.allowsBackgroundLocationUpdates {
            locationManager.allowsBackgroundLocationUpdates = true
        }
        locationManager.showsBackgroundLocationIndicator = true
    }

    private func disableBackgroundLocation() {
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.showsBackgroundLocationIndicator = false
    }

    /// `CLBackgroundActivitySession`은 Always 권한 + UIBackgroundModes(location)일 때만 생성합니다.
    private func ensureBackgroundActivitySession() {
        guard canUseBackgroundLocationTracking else { return }
        guard backgroundActivitySession == nil else { return }
        backgroundActivitySession = CLBackgroundActivitySession()
    }

    private func handleAuthorizationStatusChange() {
        switch authorizationStatus {
        case .authorizedWhenInUse:
            if sessionData.state == .recording {
                restartLocationTrackingForActiveWorkout()
            } else {
                prepareDashboardMapLocation()
            }
        case .authorizedAlways:
            if sessionData.state == .recording {
                enableBackgroundLocationIfAuthorized()
                restartLocationTrackingForActiveWorkout()
            } else {
                prepareDashboardMapLocation()
            }
        default:
            lastKnownMapLocation = nil
            stopMapLocationUpdates()
        }
    }
#endif

    private func applyRecordingLocationConfiguration() {
        locationManager.activityType = .fitness
        locationManager.distanceFilter = Self.routeTrackingDistanceFilter
#if os(iOS)
        locationManager.desiredAccuracy = routeTrackingAccuracy
        // HKWorkoutSession·Always 권한 중 하나라도 있으면 화면 꺼짐 후에도 GPS를 유지합니다.
        locationManager.pausesLocationUpdatesAutomatically = false
#else
        // watchOS는 HKWorkoutSession(야외 등산)이 켜져 있으면 화면 꺼짐 후에도 GPS·심박 수집이 계속됩니다.
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
#endif
    }

#if os(watchOS)
    /// CoreLocation은 watchOS에서도 `UIBackgroundModes`(location)를 검사합니다 —
    /// 이 키가 없으면 `allowsBackgroundLocationUpdates = true` 설정 순간
    /// `CLClientIsBackgroundable` 단언으로 앱이 종료됩니다.
    private var supportsWatchBackgroundLocationMode: Bool {
        guard let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            return false
        }
        return modes.contains("location")
    }

    /// `allowsBackgroundLocationUpdates`는 HKWorkoutSession이 실제로 시작된 뒤에만 설정합니다.
    /// 객체 생성만으로는 `CLClientIsBackgroundable`이 false라 `stayUp` 예외로 앱이 종료됩니다.
    private func enableWatchBackgroundLocationIfNeeded() {
        guard sessionData.state == .recording || sessionData.state == .paused else { return }
        guard supportsWatchBackgroundLocationMode else { return }
        guard watchWorkoutSession?.hasStartedActivity == true else { return }
        if !locationManager.allowsBackgroundLocationUpdates {
            locationManager.allowsBackgroundLocationUpdates = true
            Self.diagnosticLogger.notice("background location enabled")
        }
    }

    private func disableWatchBackgroundLocation() {
        if locationManager.allowsBackgroundLocationUpdates {
            locationManager.allowsBackgroundLocationUpdates = false
        }
    }
#endif

    /// 기록·카운트다운 중 자동 잠금을 막아 화면이 갑자기 꺼지지 않게 합니다.
    private func updateScreenSleepPrevention() {
#if os(iOS)
        let shouldPrevent = startCountdownRemaining != nil
            || sessionData.state == .recording
            || sessionData.state == .paused
        UIApplication.shared.isIdleTimerDisabled = shouldPrevent
#endif
    }

    private func startiPhoneWorkoutKeepAliveIfNeeded() {
#if os(iOS)
        guard sessionData.state == .recording || sessionData.state == .paused else { return }
        guard iPhoneWorkoutKeepAlive == nil else { return }

        let keeper = PhoneWorkoutKeepAliveSession()
        iPhoneWorkoutKeepAlive = keeper
        let startDate = sessionData.effectiveStartedAt ?? Date()
        Task {
            await keeper.start(at: startDate)
        }
#endif
    }

    private func pauseiPhoneWorkoutKeepAlive() {
#if os(iOS)
        iPhoneWorkoutKeepAlive?.pause()
#endif
    }

    private func resumeiPhoneWorkoutKeepAlive() {
#if os(iOS)
        iPhoneWorkoutKeepAlive?.resume()
#endif
    }

    private func stopiPhoneWorkoutKeepAlive() {
#if os(iOS)
        guard let keeper = iPhoneWorkoutKeepAlive else { return }
        iPhoneWorkoutKeepAlive = nil
        Task {
            await keeper.end()
        }
#endif
    }

    private func restartLocationTrackingForActiveWorkout() {
        guard sessionData.state == .recording, isLocationProducer else { return }
        authorizationStatus = locationManager.authorizationStatus
        applyRecordingLocationConfiguration()
        locationManager.stopUpdatingLocation()
#if os(iOS)
        enableBackgroundLocationIfAuthorized()
#else
        enableWatchBackgroundLocationIfNeeded()
#endif
        locationManager.startUpdatingLocation()
    }

    private func beginWorkout(syncRemote: Bool, asLocationProducer: Bool) {
        Self.diagnosticLogger.notice(
            "beginWorkout state=\(String(describing: self.sessionData.state), privacy: .public) producer=\(asLocationProducer) auth=\(self.locationManager.authorizationStatus.rawValue)"
        )
        // 상대 기기에서 먼저 시작된 경우 로컬 카운트다운은 중단합니다.
        startCountdownTask?.cancel()
        startCountdownTask = nil
        startCountdownRemaining = nil
        // 새 기록을 시작하면 이전 요약 검토 상태는 정리합니다.
        isAwaitingSummaryConfirmation = false
        summarySession = nil
        isLocationProducer = asLocationProducer
        authorizationStatus = locationManager.authorizationStatus

        if sessionData.state == .idle {
            persistDismissedSessionID(nil)
            let startDate = Date()
            sessionData = HikingSessionData(
                sessionID: UUID(),
                state: .recording,
                startedAt: startDate,
                lastUpdated: startDate
            )
            workoutStartDate = startDate
            accumulatedPausedTime = 0
            pauseBeganAt = nil
            liveDistanceAnchor = nil
#if os(watchOS)
            isAssistingLocation = false
            assistPoints = []
#endif
            clearLiveSessionBackup()
#if os(iOS)
            resetPhoneRecordingFailoverState()
#endif
        } else {
            sessionData.state = .recording
            sessionData.lastUpdated = Date()
        }

        if isLocationProducer, canRecordWithCurrentLocationAuthorization {
#if os(iOS)
            isMapLocationTrackingActive = false
            enableBackgroundLocationIfAuthorized()
#else
            disableWatchBackgroundLocation()
#endif
            applyRecordingLocationConfiguration()
            locationManager.startUpdatingLocation()
        }

#if os(iOS)
        isWatchLocationAssistActive = false
        resetGPSQualityMonitorForAssist()
        if let wcSession {
            refreshWatchCounterpartState(wcSession)
        }
        enableHeartRateMonitoringIfWatchAvailable()
        if isLocationProducer {
            startWatchWorkoutForLiveHeartRate()
        }
#endif

        startElapsedTimer()
        prepareHeartRateMonitoringForWorkout()
#if os(watchOS)
        lastHeartRateSnapshotPublishedAt = nil
        lastElapsedSnapshotPublishedAt = nil
        watchWorkoutSessionRestartAttempts = 0
        startWatchWorkoutSessionIfNeeded()
#else
        startHeartRateCollectionIfNeeded()
#endif

        startStepCountingIfNeeded()

        publishSessionSnapshot()
        startiPhoneWorkoutKeepAliveIfNeeded()
        updateScreenSleepPrevention()
        if syncRemote {
            broadcastCommand(.startRecording)
        }
    }

    private func setPaused(syncRemote: Bool) {
        sessionData.state = .paused
        sessionData.lastUpdated = Date()
        pauseBeganAt = Date()

        if isLocationProducer {
            recordPauseMarker()
            locationManager.stopUpdatingLocation()
        }
        stopElapsedTimer()
        stepCounter.stopLiveUpdates()
#if os(iOS)
        pauseiPhoneWorkoutKeepAlive()
        // 일시정지 중에는 워치 GPS 보조를 무조건 중단합니다(보조 요청 여부와 무관하게 안전).
        if isLocationProducer {
            stopWatchLocationAssist()
        }
#endif
#if os(watchOS)
        stopLocationAssistCollection()
        pauseWatchWorkoutSession()
#else
        pauseHeartRateCollection()
#endif

        saveLiveSessionBackupIfNeeded(force: true)
        publishSessionSnapshot()
        updateScreenSleepPrevention()
        purgePointsCollectedDuringPauses()
        if syncRemote {
            broadcastCommand(.pauseRecording)
        }
        startPauseActivityMonitoring()
    }

    private func setResumed(syncRemote: Bool) {
        stopPauseActivityMonitoring()
        resumeHikingPrompt = nil
        if let pauseStart = pauseBeganAt {
            accumulatedPausedTime += Date().timeIntervalSince(pauseStart)
        }
        pauseBeganAt = nil
        sessionData.state = .recording
        sessionData.lastUpdated = Date()
        closeOpenSegmentBreak(at: Date())

        if isLocationProducer {
            awaitingResumeMarker = sessionData.segmentBreaks?.last?.resumeLatitude == nil
            restartLocationTrackingForActiveWorkout()
#if os(iOS)
            resetGPSQualityMonitorForAssist()
#endif
        }
        startElapsedTimer()
        startStepCountingIfNeeded()
#if os(iOS)
        enableBackgroundLocationIfAuthorized()
        resumeiPhoneWorkoutKeepAlive()
#endif
#if os(watchOS)
        resumeWatchWorkoutSession()
#else
        resumeHeartRateCollection()
#endif

        saveLiveSessionBackupIfNeeded(force: true)
        publishSessionSnapshot()
        updateScreenSleepPrevention()
        purgePointsCollectedDuringPauses()
        if syncRemote {
            broadcastCommand(.resumeRecording)
        }
    }

    /// 상대 기기에서 종료가 전달됐을 때(원격 경로) — 즉시 저장·전송·초기화합니다.
    private func setEnded(syncRemote: Bool) {
        if syncRemote {
            finalizeSessionBeforeEnd()
        } else if let pauseStart = pauseBeganAt {
            accumulatedPausedTime += Date().timeIntervalSince(pauseStart)
            pauseBeganAt = nil
        }

        // 원격 종료 경로에서는 호출 측이 상대 기기 포인트를 먼저 병합한 뒤에 도달합니다.
        postProcessTrackForEnd()
        stopWorkoutTracking()

        let finishedSession = sessionData
        persistDismissedSessionID(finishedSession.sessionID)
        archiveFinishedSession(finishedSession, presentList: true)

        if syncRemote {
            broadcastEndSession(finishedSession)
        } else if !isApplyingRemoteUpdate {
            transferFullSessionSnapshot(finishedSession)
        }
        publishSessionEndedMarker(for: finishedSession.sessionID)

        resetSessionToIdle()
    }

    /// GPS·타이머·심박·백그라운드 세션 등 모든 추적을 멈춥니다(세션 데이터는 보존).
    private func stopWorkoutTracking() {
        stopPauseActivityMonitoring()
        resumeHikingPrompt = nil
        if isLocationProducer {
            locationManager.stopUpdatingLocation()
        }
        stepCounter.stopLiveUpdates()
        stopElapsedTimer()
#if os(watchOS)
        stopLocationAssistCollection()
        stopWatchWorkoutSession()
        disableWatchBackgroundLocation()
#else
        stopHeartRateCollection()
#endif

#if os(iOS)
        // 종료 시에는 워치 GPS 보조를 무조건 중단합니다.
        if isLocationProducer {
            stopWatchLocationAssist()
        }
        backgroundActivitySession?.invalidate()
        backgroundActivitySession = nil
        disableBackgroundLocation()
        stopiPhoneWorkoutKeepAlive()
        updateScreenSleepPrevention()
#endif
    }

    /// 세션을 대기 상태로 초기화하고 진행 중 백업을 삭제합니다.
    private func resetSessionToIdle() {
        stopPauseActivityMonitoring()
        resumeHikingPrompt = nil
        resumeHikingPromptSuppressedUntil = nil
        isAwaitingSummaryConfirmation = false
        summarySession = nil
        sessionData = HikingSessionData()
        workoutStartDate = nil
        accumulatedPausedTime = 0
        pauseBeganAt = nil
        liveDistanceAnchor = nil
#if os(iOS)
        isWatchLocationAssistActive = false
        lastAcceptedLocalPointAt = nil
        poorAccuracyStreakStartedAt = nil
        goodAccuracyStreakStartedAt = nil
        resetPhoneRecordingFailoverState()
#endif
#if os(watchOS)
        isAssistingLocation = false
        assistPoints = []
#endif
        clearLiveSessionBackup()
#if os(iOS)
        prepareDashboardMapLocation()
        updateScreenSleepPrevention()
#endif
    }

    private func archiveFinishedSession(_ session: HikingSessionData, presentList: Bool) {
#if os(iOS)
        Self.sessionArchiveHandler?(session)
        if presentList {
            shouldPresentRecordsList = true
        }
#endif
    }

#if os(iOS)
    /// Watch 단독 기록 종료 — 모음 탭에서 사용자가 가져올 때까지 보관합니다.
    private func archiveWatchFinishedSessionIfNeeded(_ remote: HikingSessionData) {
        guard shouldPublish(remote) else { return }
        guard let encoded = try? remote.encoded() else { return }
        WatchRecordInbox.shared.enqueue(session: remote, encoded: encoded)
    }

    private func handleReceivedStopRecordingUserInfo(_ userInfo: [String: Any]) {
        if sessionData.state != .idle,
           let remoteSnapshot = HikingSessionData(userInfo: userInfo),
           remoteSnapshot.sessionID == sessionData.sessionID {
            mergeFinalSessionFromRemote(remoteSnapshot)
            handleRemoteCommand(.stopRecording)
            return
        }

        if let data = userInfo[HikingConnectivityKeys.sessionTransfer] as? Data {
            WatchRecordInbox.enqueueEncodedSession(data)
        } else if let remoteSnapshot = HikingSessionData(userInfo: userInfo) {
            archiveWatchFinishedSessionIfNeeded(remoteSnapshot)
        }

        handleRemoteCommand(.stopRecording)
    }
#endif

    /// `transferFile`로 도착한 전체 세션 — 활성 세션이면 병합 후 종료, 아니면 모음 가져오기 대기열에 둡니다.
    private func handleReceivedFullSessionTransfer(_ remote: HikingSessionData) {
        if sessionData.state != .idle, remote.sessionID == sessionData.sessionID {
            mergeFinalSessionFromRemote(remote)
            handleRemoteCommand(.stopRecording)
            return
        }

#if os(iOS)
        guard let encoded = try? remote.encoded() else { return }
        WatchRecordInbox.shared.enqueue(session: remote, encoded: encoded)
#endif
    }

    // MARK: - 기록 중 세션 로컬 백업

    /// 앱이 강제 종료·크래시돼도 기록을 잃지 않도록 진행 중 세션을 디스크에 저장합니다.
    private struct LiveSessionBackup: Codable, Sendable {
        var session: HikingSessionData
        var isLocationProducer: Bool
        var accumulatedPausedTime: TimeInterval
        var workoutStartDate: Date?
        var savedAt: Date
        /// 요약 화면 검토 대기 — 재실행 시 기록 중이 아니라 요약으로 복원합니다.
        var isAwaitingSummaryConfirmation: Bool = false
        var didFailoverToPhoneRecording: Bool? = nil
        var phoneRecordingFailoverAt: Date? = nil
    }

    private nonisolated static var liveSessionBackupURL: URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("live-session-backup.json")
    }

    private func saveSummaryPendingBackup(_ finished: HikingSessionData) {
        guard isAwaitingSummaryConfirmation else { return }
        lastLiveBackupSavedAt = Date()

        let backup = LiveSessionBackup(
            session: finished,
            isLocationProducer: isLocationProducer,
            accumulatedPausedTime: accumulatedPausedTime,
            workoutStartDate: workoutStartDate,
            savedAt: Date(),
            isAwaitingSummaryConfirmation: true
        )
        guard let data = try? JSONEncoder.hikingConnectivity.encode(backup) else { return }
        try? data.write(to: Self.liveSessionBackupURL, options: .atomic)
    }

    private func saveLiveSessionBackupIfNeeded(force: Bool = false) {
        guard sessionData.state != .idle else { return }
        guard !isAwaitingSummaryConfirmation else { return }
        let now = Date()
        if !force,
           let last = lastLiveBackupSavedAt,
           now.timeIntervalSince(last) < Self.liveBackupMinInterval {
            return
        }
        lastLiveBackupSavedAt = now

        let backup = LiveSessionBackup(
            session: sessionData,
            isLocationProducer: isLocationProducer,
            accumulatedPausedTime: accumulatedPausedTime,
            workoutStartDate: workoutStartDate,
            savedAt: now,
            didFailoverToPhoneRecording: backupPhoneFailoverActive,
            phoneRecordingFailoverAt: backupPhoneFailoverAt
        )
        guard let data = try? JSONEncoder.hikingConnectivity.encode(backup) else { return }
        try? data.write(to: Self.liveSessionBackupURL, options: .atomic)
    }

    private func clearLiveSessionBackup() {
        lastLiveBackupSavedAt = nil
        try? FileManager.default.removeItem(at: Self.liveSessionBackupURL)
    }

#if os(iOS)
    private var backupPhoneFailoverActive: Bool? { isPhoneRecordingFailoverActive }
    private var backupPhoneFailoverAt: Date? { phoneRecordingFailoverAt }
#else
    private var backupPhoneFailoverActive: Bool? { nil }
    private var backupPhoneFailoverAt: Date? { nil }
#endif

    /// 앱 시작 시 백업이 있으면 — 최근 백업은 기록을 이어가고, 오래된 백업은 완료된 기록으로 처리합니다.
    private func restoreLiveSessionBackupIfNeeded() async {
        guard sessionData.state == .idle else { return }
        guard summarySession == nil else { return }
        let url = Self.liveSessionBackupURL
        let file = await Task.detached(priority: .utility) { () -> (exists: Bool, data: Data?) in
            guard FileManager.default.fileExists(atPath: url.path) else { return (false, nil) }
            return (true, try? Data(contentsOf: url))
        }.value
        guard file.exists else { return }
        guard let data = file.data,
              let backup = try? JSONDecoder.hikingConnectivity.decode(LiveSessionBackup.self, from: data)
        else {
            clearLiveSessionBackup()
            return
        }

        if backup.isAwaitingSummaryConfirmation || backup.session.state == .idle {
            restoreSummaryPendingBackup(backup)
            return
        }

        guard backup.session.state != .idle,
              !backup.session.points.isEmpty
        else {
            clearLiveSessionBackup()
            return
        }

        if let dismissedSessionID, backup.session.sessionID == dismissedSessionID {
            clearLiveSessionBackup()
            return
        }

        // 미러 백업(상대 기기가 위치 생산자) — 이 기기는 기록 소유자가 아니므로 요약·저장으로
        // 확정하지 않고 진행 중 상태로 복원합니다. 이후 WC 동기화가 최신 상태(계속 기록 중이면
        // 실시간 갱신, 상대가 종료했으면 요약 전환·폐기)를 따라갑니다.
        if !backup.isLocationProducer {
            resumeLiveSessionFromBackup(backup)
            return
        }

        // 구버전: 종료 직후 recording 상태로 저장된 요약 대기 백업
        if backup.session.state == .recording,
           backup.savedAt.timeIntervalSince(backup.session.lastUpdated) <= 3 {
            restoreSummaryPendingBackup(
                LiveSessionBackup(
                    session: {
                        var finished = backup.session
                        finished.state = .idle
                        finished.finalizeForPersistence()
                        return finished
                    }(),
                    isLocationProducer: backup.isLocationProducer,
                    accumulatedPausedTime: backup.accumulatedPausedTime,
                    workoutStartDate: backup.workoutStartDate,
                    savedAt: backup.savedAt,
                    isAwaitingSummaryConfirmation: true
                )
            )
            return
        }

        let age = Date().timeIntervalSince(backup.savedAt)
        let shouldResume = backup.session.state == .paused || age <= Self.liveBackupMaxResumeAge

        if shouldResume {
            resumeLiveSessionFromBackup(backup)
            return
        }

        // 오래된 백업 — 마지막 포인트 시각까지를 기록으로 확정해 저장(iOS)하거나 iPhone으로 전송(Watch).
        var finished = backup.session
        finished.state = .idle
        if let started = finished.effectiveStartedAt,
           let lastPoint = finished.points.last {
            finished.elapsedTime = max(
                lastPoint.timestamp.timeIntervalSince(started) - backup.accumulatedPausedTime,
                0
            )
        }
        persistDismissedSessionID(finished.sessionID)
        archiveRestoredBackupSession(finished)
    }

    /// 백업된 세션을 진행 중 상태 그대로 복원합니다(기록 재개 또는 미러 복원).
    private func resumeLiveSessionFromBackup(_ backup: LiveSessionBackup) {
        sessionData = backup.session
        // 기록 중 상태인데 마지막 일시정지 마킹이 닫히지 않았으면(구버전 재개 버그 데이터)
        // 이후 GPS 포인트가 전부 걸러지므로 백업 시각 기준으로 닫아 복구합니다.
        if sessionData.state == .recording {
            closeOpenSegmentBreak(at: backup.savedAt)
        }
        isLocationProducer = backup.isLocationProducer
        accumulatedPausedTime = backup.accumulatedPausedTime
        workoutStartDate = backup.workoutStartDate ?? backup.session.effectiveStartedAt
        liveDistanceAnchor = HikingSessionMetrics
            .horizontalDistanceWithAnchor(from: backup.session.points).anchor
#if os(iOS)
        isPhoneRecordingFailoverActive = backup.didFailoverToPhoneRecording ?? false
        phoneRecordingFailoverAt = backup.phoneRecordingFailoverAt
#endif
        if backup.session.state == .paused, pauseBeganAt == nil {
            pauseBeganAt = backup.savedAt
        }
        syncLocalTrackingToState()
    }

    private func restoreSummaryPendingBackup(_ backup: LiveSessionBackup) {
        guard backup.session.elapsedTime > 0
            || backup.session.totalDistance > 0
            || !backup.session.points.isEmpty
            || !backup.session.photos.isEmpty
        else {
            clearLiveSessionBackup()
            return
        }

        if let dismissedSessionID, backup.session.sessionID == dismissedSessionID {
            clearLiveSessionBackup()
            return
        }

        summarySession = backup.session
        isAwaitingSummaryConfirmation = true
        isLocationProducer = backup.isLocationProducer
        accumulatedPausedTime = backup.accumulatedPausedTime
        workoutStartDate = backup.workoutStartDate ?? backup.session.effectiveStartedAt
        sessionData = HikingSessionData()
    }

    /// 앱 시작 직후에는 저장 핸들러·WCSession 활성화가 끝나지 않았을 수 있어 준비될 때까지
    /// 재시도하고, 성공한 경우에만 백업을 삭제합니다(실패 시 다음 실행에서 다시 시도).
    private func archiveRestoredBackupSession(_ finished: HikingSessionData) {
        Task { @MainActor [weak self] in
            for _ in 0..<30 {
                guard let self else { return }
#if os(iOS)
                if let handler = Self.sessionArchiveHandler, UserDataPaths.isUserSelected {
                    var finalized = finished
                    finalized.finalizeForPersistence()
                    handler(finalized)
                    self.clearLiveSessionBackup()
                    return
                }
#else
                if self.canSyncWithWatch {
                    self.transferSessionReliably(finished, command: .stopRecording)
                    self.clearLiveSessionBackup()
                    return
                }
#endif
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - 일시정지 중 산행 이동 감지

    private func startPauseActivityMonitoring() {
        guard isLocationProducer else { return }
        guard sessionData.state == .paused else { return }

        pauseActivityMonitorActive = true
        pauseActivityLocations = []
        pauseActivityStepCount = 0
        pauseActivityOrigin = sessionData.segmentBreaks?.last?.pauseCoordinate
            ?? sessionData.points.last?.coordinate

        guard pauseActivityOrigin != nil else {
            pauseActivityMonitorActive = false
            return
        }

        locationManager.distanceFilter = Self.pauseActivityLocationDistanceFilter
#if os(iOS)
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.pausesLocationUpdatesAutomatically = true
#else
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
#endif
        locationManager.startUpdatingLocation()

        guard let pauseStart = pauseBeganAt, StepCounter.isStepCountingAvailable else { return }
        pauseActivityStepCounter.startLiveUpdates(from: pauseStart) { [weak self] steps in
            guard let self else { return }
            self.pauseActivityStepCount = steps
            self.evaluatePauseActivityForResumePrompt()
        }
    }

    private func stopPauseActivityMonitoring() {
        guard pauseActivityMonitorActive else {
            pauseActivityStepCounter.stopLiveUpdates()
            return
        }
        pauseActivityMonitorActive = false
        pauseActivityLocations = []
        pauseActivityStepCount = 0
        pauseActivityOrigin = nil
        pauseActivityStepCounter.stopLiveUpdates()

        if sessionData.state == .paused, isLocationProducer {
            locationManager.stopUpdatingLocation()
        }
    }

    private func ingestPauseActivityLocation(_ location: CLLocation) {
        guard pauseActivityMonitorActive, sessionData.state == .paused else { return }
        guard location.horizontalAccuracy > 0,
              location.horizontalAccuracy <= Self.pauseActivityMaxHorizontalAccuracy else { return }

        if let last = pauseActivityLocations.last {
            guard location.distance(from: last) >= Self.pauseActivityMinSampleSpacing else { return }
        }

        pauseActivityLocations.append(location)
        if pauseActivityLocations.count > Self.pauseActivityMaxSamples {
            pauseActivityLocations.removeFirst(pauseActivityLocations.count - Self.pauseActivityMaxSamples)
        }
        evaluatePauseActivityForResumePrompt()
    }

    private func evaluatePauseActivityForResumePrompt() {
        guard sessionData.state == .paused, pauseActivityMonitorActive else { return }
        guard resumeHikingPrompt == nil else { return }
        if let suppressedUntil = resumeHikingPromptSuppressedUntil, Date() < suppressedUntil {
            return
        }
        guard let pauseStart = pauseBeganAt,
              Date().timeIntervalSince(pauseStart) >= Self.resumePromptMinPauseDuration else {
            return
        }
        guard let origin = pauseActivityOrigin,
              let latest = pauseActivityLocations.last else { return }

        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let netDisplacement = latest.distance(from: originLocation)
        guard netDisplacement >= Self.resumePromptMinNetDisplacement else { return }
        guard pauseActivityStepCount >= Self.resumePromptMinSteps else { return }

        let directionality = pauseActivityDirectionality(from: originLocation)
        guard directionality >= Self.resumePromptMinDirectionality else { return }

        resumeHikingPrompt = ResumeHikingPrompt(
            netDisplacementMeters: netDisplacement,
            stepsSincePause: pauseActivityStepCount
        )
    }

    private func pauseActivityDirectionality(from origin: CLLocation) -> Double {
        let points = pauseActivityLocations
        guard points.count >= 2 else { return 0 }
        var pathLength: CLLocationDistance = 0
        var previous = points[0]
        for point in points.dropFirst() {
            pathLength += point.distance(from: previous)
            previous = point
        }
        guard pathLength > 1, let last = points.last else { return 0 }
        return last.distance(from: origin) / pathLength
    }

    private func handleLocationManagerDidPauseLocationUpdates() {
        if sessionData.state == .recording, isLocationProducer {
            // 시스템이 위치 업데이트를 멈춘 경우 기록용 설정으로 즉시 재시작합니다.
            restartLocationTrackingForActiveWorkout()
            return
        }
        if sessionData.state == .paused, pauseActivityMonitorActive, isLocationProducer {
            locationManager.startUpdatingLocation()
            return
        }
#if os(iOS)
        if sessionData.state == .idle, isMapLocationTrackingActive {
            locationManager.startUpdatingLocation()
        }
#endif
    }

    // MARK: - Metrics

    /// 종료 직전 경과 시간·`lastUpdated`를 확정합니다 (Watch → iPhone 지연 동기화용).
    private func finalizeSessionBeforeEnd() {
        if let pauseStart = pauseBeganAt {
            accumulatedPausedTime += Date().timeIntervalSince(pauseStart)
            pauseBeganAt = nil
        }
        purgePointsCollectedDuringPauses()
        if sessionData.state == .recording, let workoutStartDate {
            sessionData.elapsedTime = Date().timeIntervalSince(workoutStartDate) - accumulatedPausedTime
        }
        sessionData.lastUpdated = Date()
    }

    /// 종료 확정 직전 GPS 트랙 사후 보정(이상치 제거·스무딩) — 위치 생산 기기에서
    /// 상대 기기 포인트 병합이 끝난 뒤 한 번만 적용합니다(기록 중에는 적용하지 않음).
    private func postProcessTrackForEnd() {
        guard isLocationProducer else { return }
        guard sessionData.points.count >= 3 else { return }

        let processed = HikingTrackPostProcessor.process(sessionData.points)
        sessionData.points = processed
        let recomputed = HikingSessionMetrics.horizontalDistanceWithAnchor(from: processed)
        sessionData.totalDistance = recomputed.total
        liveDistanceAnchor = recomputed.anchor
        sessionData.elevationGainMeters = HikingSessionMetrics.cumulativeElevationGain(from: processed)
        // 포인트가 바뀌었으므로 표시 캐시는 무효화 — `finalizeForPersistence()`가 다시 만듭니다.
        sessionData.displayCacheVersion = nil
    }

    /// 일시정지 동안 들어온 GPS·지연 전달 포인트를 제거하고 거리를 다시 맞춥니다.
    private func purgePointsCollectedDuringPauses() {
        let cleaned = HikingSessionMetrics.pointsExcludingPausedIntervals(
            sessionData.points,
            segmentBreaks: sessionData.segmentBreaks
        )
        guard cleaned.count != sessionData.points.count else { return }
        sessionData.points = cleaned
        let recomputed = HikingSessionMetrics.horizontalDistanceWithAnchor(from: cleaned)
        sessionData.totalDistance = recomputed.total
        liveDistanceAnchor = recomputed.anchor
    }

    private func shouldAcceptGPSPoint(at timestamp: Date) -> Bool {
        !HikingSessionMetrics.isTimestampDuringPausedInterval(
            timestamp,
            segmentBreaks: sessionData.segmentBreaks
        )
    }

    private func startElapsedTimer() {
        stopElapsedTimer()
        elapsedTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tickElapsedTime()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimerTask?.cancel()
        elapsedTimerTask = nil
    }

    private func tickElapsedTime() {
        guard sessionData.state == .recording, let workoutStartDate else { return }
        sessionData.elapsedTime = Date().timeIntervalSince(workoutStartDate) - accumulatedPausedTime
        saveLiveSessionBackupIfNeeded()
        sessionData.currentPace = Self.paceMinutesPerKilometer(
            distanceMeters: sessionData.totalDistance,
            elapsedSeconds: sessionData.elapsedTime
        )
        sessionData.lastUpdated = Date()
#if os(iOS)
        // 위치 콜백이 끊긴 경우에도 채택 공백 기반 품질 저하를 판정합니다.
        evaluateGPSQualityForAssist()
        evaluateWatchLossFailover()
#endif
#if os(watchOS)
        updateWatchActiveEnergy()
        // 손목 내림 시 iPhone 동기화 빈도만 줄입니다. GPS·심박·포인트 저장은 계속됩니다.
        let minPublishInterval: TimeInterval = isWatchDisplayLuminanceReduced ? 20 : 4
        let now = Date()
        if let lastPublished = lastElapsedSnapshotPublishedAt,
           now.timeIntervalSince(lastPublished) < minPublishInterval {
            return
        }
        lastElapsedSnapshotPublishedAt = now
#endif
        publishSessionSnapshot()
    }

    private func ingestLocation(_ location: CLLocation) {
        guard sessionData.state == .recording, isLocationProducer else { return }
        guard shouldAcceptGPSPoint(at: location.timestamp) else { return }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= allowedHorizontalAccuracy(for: location) else { return }
        guard shouldStoreRecordingPoint(for: location) else { return }

        let rawAltitude: Double
        if location.verticalAccuracy > 0,
           location.verticalAccuracy <= HikingSessionMetrics.acceptableVerticalAccuracy {
            rawAltitude = location.altitude
        } else if let last = sessionData.points.last {
            rawAltitude = last.altitude
        } else {
            rawAltitude = location.altitude
        }

        var altitude = rawAltitude
        if let lastAccepted = sessionData.points.last {
            let lastLocation = CLLocation(
                latitude: lastAccepted.latitude,
                longitude: lastAccepted.longitude
            )
            let segment = location.distance(from: lastLocation)
            let elapsed = abs(location.timestamp.timeIntervalSince(lastAccepted.timestamp))
            altitude = HikingSessionMetrics.storedAltitude(
                proposed: rawAltitude,
                previousAltitude: lastAccepted.altitude,
                horizontalMeters: segment,
                elapsedSeconds: elapsed
            )
        }

        var point = HikingPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: altitude,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy
        )
        if let lastAccepted = sessionData.points.last,
           HikingTrackPostProcessor.isImplausibleSpeed(from: lastAccepted, to: point) {
            let prior = sessionData.points.count >= 2
                ? sessionData.points[sessionData.points.count - 2]
                : nil
            point = HikingGPSStatisticalCorrection.correctedPoint(
                previous: lastAccepted,
                prior: prior,
                candidate: point,
                maxSpeedMetersPerSecond: HikingTrackPostProcessor.maxPlausibleSpeedMetersPerSecond
            )
        }

        if sessionData.points.isEmpty {
            Self.diagnosticLogger.notice(
                "first GPS point accepted accuracy=\(location.horizontalAccuracy, format: .fixed(precision: 1))"
            )
        }
        accumulateLiveDistance(to: point)
        sessionData.points.append(point)
#if os(iOS)
        noteAcceptedLocalPointForAssist(accuracy: location.horizontalAccuracy)
#endif
        if awaitingResumeMarker {
            fillResumeMarker(with: point)
        }
        sessionData.currentAltitude = altitude
        sessionData.currentPace = Self.paceMinutesPerKilometer(
            distanceMeters: sessionData.totalDistance,
            elapsedSeconds: sessionData.elapsedTime
        )
        sessionData.lastUpdated = Date()

        saveLiveSessionBackupIfNeeded()
        publishSessionSnapshot()
        sendLatestPoint(point)
    }

    /// 일시정지 순간의 좌표를 마킹으로 남깁니다(위치 생산 기기에서만 호출).
    private func recordPauseMarker() {
        let coordinate: CLLocationCoordinate2D?
        if let last = sessionData.points.last {
            coordinate = last.coordinate
        } else if let location = locationManager.location {
            coordinate = location.coordinate
        } else {
            coordinate = nil
        }
        guard let coordinate else { return }

        var breaks = sessionData.segmentBreaks ?? []
        breaks.append(
            HikingSegmentBreak(
                pauseLatitude: coordinate.latitude,
                pauseLongitude: coordinate.longitude,
                pauseTime: Date()
            )
        )
        sessionData.segmentBreaks = breaks
        awaitingResumeMarker = false
    }

    /// 재개 시점에 열린 일시정지 마킹을 즉시 닫습니다. `resumeTime`이 비어 있으면
    /// 이후 GPS 포인트가 전부 '일시정지 구간'으로 걸러져 재개 후 기록이 남지 않습니다.
    /// 재개 좌표는 첫 GPS 포인트가 오면 `fillResumeMarker`가 보강합니다.
    private func closeOpenSegmentBreak(at resumeDate: Date) {
        guard var breaks = sessionData.segmentBreaks,
              var last = breaks.last,
              last.resumeTime == nil else { return }
        last.resumeTime = resumeDate
        breaks[breaks.count - 1] = last
        sessionData.segmentBreaks = breaks
    }

    /// 재개 직후 첫 포인트로 마지막 마킹의 재개 좌표를 채웁니다.
    private func fillResumeMarker(with point: HikingPoint) {
        awaitingResumeMarker = false
        guard var breaks = sessionData.segmentBreaks, !breaks.isEmpty else { return }
        var last = breaks[breaks.count - 1]
        guard last.resumeLatitude == nil else { return }
        last.resumeLatitude = point.latitude
        last.resumeLongitude = point.longitude
        // 재개 시각은 재개 버튼 시점(`closeOpenSegmentBreak`)이 기준 — 캐시된 과거 시각의
        // 포인트로 앞당기면 일시정지 구간 포인트 정리가 무력화되므로 비어 있을 때만 채웁니다.
        if last.resumeTime == nil {
            last.resumeTime = point.timestamp
        }
        breaks[breaks.count - 1] = last
        sessionData.segmentBreaks = breaks
    }

    /// anchor에서 GPS 노이즈 반경 이상 이동했을 때만 누적 거리에 더하고 anchor를 옮깁니다.
    private func accumulateLiveDistance(to point: HikingPoint) {
        guard let anchor = liveDistanceAnchor else {
            liveDistanceAnchor = point
            return
        }
        let segment = HikingSessionMetrics.segmentDistance(from: anchor, to: point)
        if segment >= HikingSessionMetrics.distanceAnchorThreshold(for: point) {
            sessionData.totalDistance += segment
            liveDistanceAnchor = point
        }
    }

    /// 평상시엔 30m 게이트로 노이즈를 막되, 일정 시간 공백이 생기면(도심 협곡 등)
    /// 경로가 통째로 비지 않도록 완화된 정확도까지 허용합니다.
    private func allowedHorizontalAccuracy(for location: CLLocation) -> CLLocationDistance {
        guard let lastAccepted = sessionData.points.last else {
            return Self.maxStorableHorizontalAccuracy
        }
        let gap = abs(location.timestamp.timeIntervalSince(lastAccepted.timestamp))
        return gap >= Self.recordingGapRescueInterval
            ? Self.maxStorableHorizontalAccuracyDuringGap
            : Self.maxStorableHorizontalAccuracy
    }

    /// 실제로 이동했을 때만 약 1초 간격으로 저장합니다.
    /// 정지 상태의 GPS 흔들림(실내 다중경로 포함)은 노이즈 반경 비례 임계값으로 걸러냅니다.
    /// 불가능한 속도의 점프는 여기서 버리지 않고, 저장 직전에 속도 한도로 보정합니다.
    private func shouldStoreRecordingPoint(for location: CLLocation) -> Bool {
        guard let lastAccepted = sessionData.points.last else { return true }

        let lastLocation = CLLocation(
            latitude: lastAccepted.latitude,
            longitude: lastAccepted.longitude
        )
        let segment = location.distance(from: lastLocation)
        let elapsed = abs(location.timestamp.timeIntervalSince(lastAccepted.timestamp))

        let accuracyThreshold = min(
            location.horizontalAccuracy * Self.recordingPointAccuracyFactor,
            Self.recordingPointMaxThreshold
        )
        let minimumMovement = max(Self.recordingPointMinDistance, accuracyThreshold)
        return elapsed >= Self.recordingPointMinInterval && segment >= minimumMovement
    }

    private static func paceMinutesPerKilometer(
        distanceMeters: Double,
        elapsedSeconds: TimeInterval
    ) -> Double? {
        let kilometers = distanceMeters / 1_000
        guard kilometers >= 0.01, elapsedSeconds > 0 else { return nil }
        return (elapsedSeconds / 60) / kilometers
    }

    // MARK: - 워치 GPS 보조 (품질 기반)

#if os(iOS)
    /// 기록 시작·재개 시 품질 모니터 상태를 초기화합니다 — 시작 직후 곧바로 저하 판정되지 않도록
    /// 마지막 채택 시각을 현재로 시드합니다.
    private func resetGPSQualityMonitorForAssist() {
        lastAcceptedLocalPointAt = Date()
        poorAccuracyStreakStartedAt = nil
        goodAccuracyStreakStartedAt = nil
    }

    /// 수신한 원시 GPS 정확도를 관찰해 품질 저하 전환을 판단합니다(채택 여부와 무관).
    private func trackRawGPSQualityForAssist(_ location: CLLocation) {
        guard sessionData.state == .recording, isLocationProducer else { return }
        let now = Date()
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > Self.assistDegradedAccuracy {
            if poorAccuracyStreakStartedAt == nil {
                poorAccuracyStreakStartedAt = now
            }
        } else {
            poorAccuracyStreakStartedAt = nil
        }
        evaluateGPSQualityForAssist(at: now)
    }

    /// 로컬 GPS 포인트 채택 시 회복 판단용 상태를 갱신합니다(`ingestLocation` 성공 경로).
    private func noteAcceptedLocalPointForAssist(accuracy: CLLocationAccuracy) {
        let now = Date()
        lastAcceptedLocalPointAt = now
        if accuracy >= 0, accuracy <= Self.assistRecoveredAccuracy {
            if goodAccuracyStreakStartedAt == nil {
                goodAccuracyStreakStartedAt = now
            }
        } else {
            goodAccuracyStreakStartedAt = nil
        }
        evaluateGPSQualityForAssist(at: now)
    }

    /// 저하/회복 전환 판정 — 위치 콜백과 경과 타이머 틱에서 호출됩니다.
    private func evaluateGPSQualityForAssist(at now: Date = Date()) {
        guard sessionData.state == .recording, isLocationProducer else { return }

        if isWatchLocationAssistActive {
            if let goodStart = goodAccuracyStreakStartedAt,
               now.timeIntervalSince(goodStart) >= Self.assistRecoverySustainInterval {
                stopWatchLocationAssist()
            }
            return
        }

        let acceptedGapDegraded: Bool
        if let lastAccepted = lastAcceptedLocalPointAt {
            acceptedGapDegraded = now.timeIntervalSince(lastAccepted) >= Self.assistNoAcceptedPointInterval
        } else {
            // 시드 전이면 지금부터 공백을 재기 시작합니다.
            lastAcceptedLocalPointAt = now
            acceptedGapDegraded = false
        }
        let poorAccuracyDegraded = poorAccuracyStreakStartedAt.map {
            now.timeIntervalSince($0) >= Self.assistDegradedSustainInterval
        } ?? false

        if acceptedGapDegraded || poorAccuracyDegraded {
            startWatchLocationAssist()
        }
    }

    /// 품질 저하 전환 — 워치에 임시 GPS 보조 수집을 요청합니다.
    private func startWatchLocationAssist() {
        guard isWatchCounterpartInstalled, isWatchActivelyLinked else { return }
        isWatchLocationAssistActive = true
        goodAccuracyStreakStartedAt = nil
        broadcastCommand(.startLocationAssist)
    }

    /// 회복·일시정지·종료 — 워치 GPS 보조 수집을 중단시킵니다.
    /// 보조 요청 여부와 무관하게 안전하게 중단 명령을 보낼 수 있습니다(워치에서 무시).
    private func stopWatchLocationAssist() {
        isWatchLocationAssistActive = false
        poorAccuracyStreakStartedAt = nil
        goodAccuracyStreakStartedAt = nil
        broadcastCommand(.stopLocationAssist)
    }

    /// 워치가 꺼지거나 장시간 비활성이면 같은 세션을 iPhone GPS로 이어받습니다.
    private func evaluateWatchLossFailover(at now: Date = Date()) {
        guard sessionData.state == .recording || sessionData.state == .paused else {
            resetWatchLossMonitor()
            return
        }

        if isWatchReachable {
            resetWatchLossMonitor()
            notifyWatchOfPhoneTakeoverIfNeeded()
            return
        }

        if isPhoneRecordingFailoverActive {
            didNotifyWatchOfPhoneTakeover = false
            return
        }

        guard !isLocationProducer else {
            resetWatchLossMonitor()
            return
        }

        if isWatchActivelyLinked {
            resetWatchLossMonitor()
            return
        }

        if watchConnectivityLossStartedAt == nil {
            watchConnectivityLossStartedAt = now
            startiPhoneWorkoutKeepAliveIfNeeded()
            scheduleWatchLossFailoverCheck()
        }

        guard let lossStart = watchConnectivityLossStartedAt,
              now.timeIntervalSince(lossStart) >= Self.watchLossFailoverThreshold else {
            return
        }
        promotePhoneToLocationProducer()
    }

    private func scheduleWatchLossFailoverCheck() {
        guard watchLossFailoverTask == nil else { return }
        watchLossFailoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.watchLossFailoverThreshold))
            guard !Task.isCancelled else { return }
            self?.evaluateWatchLossFailover()
        }
    }

    private func resetWatchLossMonitor() {
        watchConnectivityLossStartedAt = nil
        watchLossFailoverTask?.cancel()
        watchLossFailoverTask = nil
    }

    private func resetPhoneRecordingFailoverState() {
        resetWatchLossMonitor()
        isPhoneRecordingFailoverActive = false
        phoneRecordingFailoverAt = nil
        didNotifyWatchOfPhoneTakeover = false
    }

    /// 워치 위치 생산자를 iPhone으로 바꿉니다. 세션 ID·기존 경로는 유지합니다.
    private func promotePhoneToLocationProducer() {
        guard !isPhoneRecordingFailoverActive else { return }
        guard sessionData.state == .recording || sessionData.state == .paused else { return }

        Self.diagnosticLogger.notice("phone taking over recording after watch connectivity loss")
        isLocationProducer = true
        isPhoneRecordingFailoverActive = true
        phoneRecordingFailoverAt = Date()
        didNotifyWatchOfPhoneTakeover = false
        resetWatchLossMonitor()
        stopWatchLocationAssist()
        liveDistanceAnchor = HikingSessionMetrics
            .horizontalDistanceWithAnchor(from: sessionData.points).anchor

        if sessionData.state == .recording {
            restartLocationTrackingForActiveWorkout()
            startStepCountingIfNeeded()
        }
        startiPhoneWorkoutKeepAliveIfNeeded()
        startHeartRateCollectionIfNeeded()
        saveLiveSessionBackupIfNeeded(force: true)
        publishSessionSnapshot()
        notifyWatchOfPhoneTakeoverIfNeeded()
    }

    private func notifyWatchOfPhoneTakeoverIfNeeded() {
        guard isPhoneRecordingFailoverActive, isWatchReachable else { return }
        guard !didNotifyWatchOfPhoneTakeover else { return }
        didNotifyWatchOfPhoneTakeover = true
        broadcastCommand(.phoneTookOverRecording)
    }
#endif

#if os(watchOS)
    /// iPhone GPS 품질 저하 — 임시 GPS 보조 수집을 시작합니다(비생산자·기록 중에만).
    private func startLocationAssistCollection() {
        guard sessionData.state == .recording, !isLocationProducer else { return }
        guard !isAssistingLocation else { return }
        authorizationStatus = locationManager.authorizationStatus
        guard canRecordWithCurrentLocationAuthorization else { return }
        isAssistingLocation = true
        // 손목 내림·화면 꺼짐 후에도 GPS가 유지되도록 HKWorkoutSession이 없으면 시작합니다.
        startWatchWorkoutSessionIfNeeded()
        enableWatchBackgroundLocationIfNeeded()
        applyRecordingLocationConfiguration()
        locationManager.startUpdatingLocation()
    }

    /// GPS 보조 수집 중단 — 버퍼는 세션에 합치고, 위치 생산자가 아니면 위치 업데이트도 멈춥니다.
    private func stopLocationAssistCollection() {
        guard isAssistingLocation else { return }
        isAssistingLocation = false
        mergeAssistPointsIntoSession()
        if !isLocationProducer {
            locationManager.stopUpdatingLocation()
        }
    }

    /// 보조 수집 GPS 픽스를 버퍼에 저장하고 iPhone으로 실시간 전송합니다.
    /// `sessionData.points`에는 넣지 않습니다 — 보조 중단·종료 시 한꺼번에 합칩니다.
    private func ingestAssistLocation(_ location: CLLocation) {
        guard isAssistingLocation, !isLocationProducer, sessionData.state == .recording else { return }
        guard shouldAcceptGPSPoint(at: location.timestamp) else { return }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.assistMaxHorizontalAccuracy else { return }
        if let last = assistPoints.last {
            guard location.timestamp.timeIntervalSince(last.timestamp) >= Self.recordingPointMinInterval
            else { return }
        }

        let point = HikingPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy
        )
        assistPoints.append(point)
        sendLatestPoint(point)
    }

    /// 보조 수집 포인트를 세션 포인트에 합쳐 이후 스냅샷·최종 병합에 포함되도록 합니다.
    private func mergeAssistPointsIntoSession() {
        guard !assistPoints.isEmpty else { return }
        let existingIDs = Set(sessionData.points.map(\.id))
        let newPoints = assistPoints.filter { !existingIDs.contains($0.id) }
        guard !newPoints.isEmpty else { return }
        sessionData.points.append(contentsOf: newPoints)
        sessionData.points.sort { $0.timestamp < $1.timestamp }
        sessionData.lastUpdated = Date()
    }

    /// iPhone이 워치 배터리 방전 등으로 위치 기록을 이어받음 — GPS를 멈추고 미러로 전환합니다.
    private func adoptPhoneLocationProducerTakeover() {
        guard sessionData.state == .recording || sessionData.state == .paused else { return }
        isLocationProducer = false
        stopLocationAssistCollection()
        stepCounter.stopLiveUpdates()
        locationManager.stopUpdatingLocation()
        saveLiveSessionBackupIfNeeded(force: true)
        syncLocalTrackingToState()
        Self.diagnosticLogger.notice("watch demoted to mirror after phone recording takeover")
    }
#endif

    // MARK: - WatchConnectivity

    private func configureWatchConnectivity() {
        guard WCSession.isSupported() else {
            isWatchConnectivitySupported = false
            isWatchCounterpartInstalled = false
            isWatchLinkEstablished = false
            isWatchReachable = false
            return
        }

        let session = WCSession.default
        wcSession = session
        isWatchConnectivitySupported = true
        session.delegate = self
        session.activate()
    }

    /// WC 전송 가능 여부 — 캐시가 아닌 세션의 최신 값으로 판단합니다.
    /// 시뮬레이터에서 `isWatchAppInstalled`만 true이고 실제로는 미설치인 경우가 있어 `isPaired`도 확인합니다.
    private var canSyncWithWatch: Bool {
        guard let wcSession, wcSession.activationState == .activated else { return false }
#if os(iOS)
        return wcSession.isWatchAppInstalled && wcSession.isPaired
#else
        return wcSession.isCompanionAppInstalled
#endif
    }

    private func refreshWatchCounterpartState(_ session: WCSession) {
#if os(iOS)
        let counterpartInstalled = session.isWatchAppInstalled && session.isPaired
#else
        let counterpartInstalled = session.isCompanionAppInstalled
#endif
        isWatchCounterpartInstalled = counterpartInstalled

        let syncCapable = session.activationState == .activated && counterpartInstalled
        isWatchLinkEstablished = syncCapable
        isWatchReachable = session.isReachable && syncCapable

        if isWatchReachable {
            requestSessionSyncFromCounterpart()
        }
#if os(iOS)
        evaluateWatchLossFailover()
        if sessionData.state == .recording {
            enableHeartRateMonitoringIfWatchAvailable()
            startHeartRateCollectionIfNeeded()
        }
        if sessionData.state == .recording, !shouldUseHealthKitHeartRateFallback() {
            stopHeartRateCollection()
        }
#endif
    }

    /// 상대 기기에 최신 세션 스냅샷을 즉시 요청해 기록 상태를 동기화합니다.
    private func requestSessionSyncFromCounterpart() {
        guard let wcSession, canSyncWithWatch, wcSession.isReachable else { return }
        let payload = HikingSessionCommand.requestSync.dictionary
        guard !payload.isEmpty else { return }

        wcSession.sendMessage(payload, replyHandler: { [weak self] reply in
            guard let data = reply[HikingConnectivityKeys.sessionSnapshot] as? Data,
                  let snapshot = try? HikingSessionData.decoded(from: data) else { return }
            Task { @MainActor in
                self?.markWatchSyncActivity()
                self?.applyRemoteSession(snapshot, mergePoints: true)
            }
        }, errorHandler: { _ in })
    }

    private func applyReceivedApplicationContextIfAvailable(_ session: WCSession) {
        // 앱 시작 시 캐시된 상대 기기 스냅샷으로 GPS·타이머가 자동 시작되지 않도록 합니다.
        guard sessionData.state != .idle else { return }
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return }
        guard let snapshot = HikingSessionData(applicationContext: context) else { return }
        applyRemoteSession(snapshot, mergePoints: true)
    }

    private func publishSessionSnapshot() {
        guard canSyncWithWatch, let wcSession else { return }
        guard shouldPublish(sessionData) else { return }

        var snapshot = sessionData
        if snapshot.points.count > 80 {
            snapshot.points = Array(snapshot.points.suffix(80))
        }
        if snapshot.heartRateSamples.count > Self.publishedHeartRateSampleLimit {
            snapshot.heartRateSamples = Array(
                snapshot.heartRateSamples.suffix(Self.publishedHeartRateSampleLimit)
            )
        }

        let context = snapshot.applicationContext
        guard !context.isEmpty else { return }

        do {
            try wcSession.updateApplicationContext(context)
            markWatchSyncActivity()
        } catch {
            guard canSyncWithWatch else { return }
            guard !isWatchConnectivityUnavailableError(error) else { return }
            wcSession.transferUserInfo(snapshot.userInfo)
            markWatchSyncActivity()
        }
    }

    private func transferFullSessionSnapshot(_ session: HikingSessionData? = nil) {
        transferSessionReliably(session ?? sessionData, command: nil)
    }

    /// 세션 전체를 상대 기기로 확실히 전달합니다.
    /// `transferUserInfo`는 페이로드 한도(약 65KB)가 있어 장시간 기록은 조용히 유실되므로,
    /// 큰 세션은 `transferFile`(크기 제한 없음·시스템 재전송)로 보내고
    /// 빠른 상태 반영을 위해 잘린 스냅샷도 함께 보냅니다.
    private func transferSessionReliably(_ session: HikingSessionData, command: HikingSessionCommand?) {
        guard canSyncWithWatch, let wcSession else { return }
        guard shouldPublish(session) else { return }

        let fitsInUserInfo = session.points.count <= Self.maxUserInfoTransferPointCount
            && session.heartRateSamples.count <= Self.maxUserInfoTransferHeartRateSampleCount

        if fitsInUserInfo {
            wcSession.transferUserInfo(sessionUserInfoPayload(session, command: command))
            return
        }

        transferSessionFile(session, via: wcSession)

        var trimmed = session
        trimmed.points = Array(session.points.suffix(Self.maxUserInfoTransferPointCount))
        trimmed.heartRateSamples = Array(
            session.heartRateSamples.suffix(Self.maxUserInfoTransferHeartRateSampleCount)
        )
        wcSession.transferUserInfo(sessionUserInfoPayload(trimmed, command: command))
    }

    private func sessionUserInfoPayload(
        _ session: HikingSessionData,
        command: HikingSessionCommand?
    ) -> [String: Any] {
        if let command {
            return session.userInfo(including: command)
        }
        return session.userInfo
    }

    private func transferSessionFile(_ session: HikingSessionData, via wcSession: WCSession) {
        guard let data = try? session.encoded() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hiking-session-\(session.sessionID.uuidString).json")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
        wcSession.transferFile(
            url,
            metadata: [HikingConnectivityKeys.command: HikingSessionCommand.stopRecording.rawValue]
        )
    }

    private func publishSessionEndedMarker(for sessionID: UUID) {
        guard canSyncWithWatch, let wcSession else { return }
        let marker = HikingSessionData(
            sessionID: sessionID,
            state: .idle,
            lastUpdated: Date()
        )
        let context = marker.applicationContext
        guard !context.isEmpty else { return }
        try? wcSession.updateApplicationContext(context)
    }

    private func transferEndSession(_ session: HikingSessionData) {
        transferSessionReliably(session, command: .stopRecording)
    }

    private func broadcastEndSession(_ session: HikingSessionData) {
        guard let wcSession, canSyncWithWatch, !isApplyingRemoteUpdate else { return }

        let commandPayload = HikingSessionCommand.stopRecording.dictionary
        guard !commandPayload.isEmpty else { return }

        if wcSession.isReachable {
            wcSession.sendMessage(commandPayload, replyHandler: nil) { error in
                guard !Self.isWatchConnectivityUnavailableError(error) else { return }
            }
            transferEndSession(session)
        } else {
            transferEndSession(session)
        }
    }

    /// 요약 화면 폐기 — 상대 기기에 저장 없이 초기화하라고 알립니다.
    private func broadcastDiscard() {
        guard let wcSession, canSyncWithWatch, !isApplyingRemoteUpdate else { return }
        let payload = HikingSessionCommand.discardRecording.dictionary
        guard !payload.isEmpty, wcSession.isReachable else { return }
        wcSession.sendMessage(payload, replyHandler: nil) { error in
            guard !Self.isWatchConnectivityUnavailableError(error) else { return }
        }
    }

    private func shouldPublish(_ session: HikingSessionData) -> Bool {
        session.state != .idle
            || session.elapsedTime > 0
            || session.totalDistance > 0
            || !session.points.isEmpty
            || !session.photos.isEmpty
    }

    private func sendLatestPoint(_ point: HikingPoint) {
        guard
            let wcSession,
            canSyncWithWatch,
            wcSession.isReachable,
            !isApplyingRemoteUpdate
        else { return }

        let payload = point.messagePayload
        guard !payload.isEmpty else { return }

        wcSession.sendMessage(payload, replyHandler: nil) { error in
            guard !Self.isWatchConnectivityUnavailableError(error) else { return }
        }
    }

#if os(watchOS)
    private func sendHeartRateSample(_ sample: HikingHeartRateSample) {
        guard let wcSession, canSyncWithWatch, !isApplyingRemoteUpdate else { return }

        let payload = sample.messagePayload
        guard !payload.isEmpty else { return }

        if wcSession.isReachable {
            wcSession.sendMessage(payload, replyHandler: nil) { error in
                guard !Self.isWatchConnectivityUnavailableError(error) else { return }
            }
        } else {
            wcSession.transferUserInfo(payload)
        }
    }
#endif

    private func broadcastCommand(_ command: HikingSessionCommand) {
        guard let wcSession, canSyncWithWatch, !isApplyingRemoteUpdate else { return }

        let payload = command.dictionary
        guard !payload.isEmpty else { return }

        if wcSession.isReachable {
            wcSession.sendMessage(payload, replyHandler: nil) { error in
                guard !Self.isWatchConnectivityUnavailableError(error) else { return }
            }
        } else if shouldPublish(sessionData) {
            publishSessionSnapshot()
        }
    }

    private func isWatchConnectivityUnavailableError(_ error: Error) -> Bool {
        Self.isWatchConnectivityUnavailableError(error)
    }

    private static func isWatchConnectivityUnavailableError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == WCErrorDomain else { return false }
        switch nsError.code {
        case WCError.Code.watchAppNotInstalled.rawValue,
             WCError.Code.notReachable.rawValue,
             WCError.Code.sessionNotActivated.rawValue:
            return true
        default:
            return false
        }
    }

    // MARK: - 심박수 사전 준비

    private func prepareHeartRateMonitoringForWorkout() {
#if os(iOS)
        guard shouldCollectHeartRateDuringWorkout else { return }
#else
        guard HeartRatePreferences.isFeatureEnabled else { return }
        guard HeartRatePreferences.isMonitoringEnabled else { return }
#endif
#if os(iOS)
        Task(priority: .userInitiated) {
            await HeartRateMonitor.shared.prepareForWorkout()
        }
#else
        Task(priority: .userInitiated) {
            await WatchHeartRateWorkoutSession.prepareAuthorizationIfNeeded()
        }
#endif
    }

    // MARK: - Watch 운동 세션 (백그라운드 유지)

#if os(watchOS)
    private func startWatchWorkoutSessionIfNeeded() {
        guard sessionData.state == .recording || sessionData.state == .paused else { return }
        guard watchWorkoutSession == nil else { return }

        let workoutSession = WatchHeartRateWorkoutSession()
        workoutSession.setOnSample { [weak self] sample in
            self?.appendHeartRateSample(sample)
        }
        // 백그라운드 위치는 타이밍 추정이 아니라 세션이 실제 `.running`에 도달했다는
        // delegate 신호로만 켭니다 — 그 전에 켜면 CoreLocation 단언으로 앱이 종료됩니다.
        workoutSession.setOnRunningStateChange { [weak self, weak workoutSession] isRunning in
            guard let self, let workoutSession else { return }
            self.handleWatchWorkoutSessionRunningChange(isRunning, session: workoutSession)
        }
        // 잔여 세션 충돌 등으로 시작이 조용히 실패하면(didFailWithError) 세션 없이 기록이
        // 이어져 손목 내림 시 앱이 정지되고 데이터가 0으로 멈추므로, 정리 후 재시도합니다.
        workoutSession.setOnFailure { [weak self, weak workoutSession] in
            guard let self, let workoutSession else { return }
            self.handleWatchWorkoutSessionFailure(session: workoutSession)
        }
        watchWorkoutSession = workoutSession
        let startDate = sessionData.effectiveStartedAt ?? Date()
        Self.diagnosticLogger.notice("HK session start requested")
        Task(priority: .userInitiated) {
            await workoutSession.start(at: startDate)
            Self.diagnosticLogger.notice(
                "HK session start returned hasSession=\(workoutSession.hasActiveSession) running=\(workoutSession.hasStartedActivity)"
            )
            guard self.watchWorkoutSession === workoutSession,
                  self.sessionData.state == .recording || self.sessionData.state == .paused else { return }
            // 세션 생성 자체가 실패한 경우(didFailWithError 없이 조용히 종료) — 재시도 경로로 보냅니다.
            guard workoutSession.hasActiveSession else {
                self.handleWatchWorkoutSessionFailure(session: workoutSession)
                return
            }
            if self.sessionData.state == .paused {
                workoutSession.pause()
            }
        }
    }

    /// HKWorkoutSession이 실제 `.running`에 도달·이탈했을 때 — 백그라운드 위치를 켜고 끕니다.
    private func handleWatchWorkoutSessionRunningChange(
        _ isRunning: Bool,
        session: WatchHeartRateWorkoutSession
    ) {
        Self.diagnosticLogger.notice(
            "HK session running=\(isRunning) state=\(String(describing: self.sessionData.state), privacy: .public)"
        )
        guard watchWorkoutSession === session else { return }
        guard isRunning else {
            disableWatchBackgroundLocation()
            return
        }
        guard sessionData.state == .recording || sessionData.state == .paused else { return }
        watchWorkoutSessionRestartAttempts = 0
        guard isLocationProducer || isAssistingLocation else { return }
        // 앱 재실행 직후에는 CLLocationManager delegate가 오기 전이라 @Published 권한이
        // .notDetermined로 남아 있을 수 있어 판단 전에 직접 갱신합니다.
        authorizationStatus = locationManager.authorizationStatus
        guard canRecordWithCurrentLocationAuthorization else { return }
        enableWatchBackgroundLocationIfNeeded()
        if sessionData.state == .recording {
            locationManager.stopUpdatingLocation()
            applyRecordingLocationConfiguration()
            locationManager.startUpdatingLocation()
        }
    }

    /// HKWorkoutSession 시작 실패(잔여 세션 충돌 등) — 잠시 후 새 세션으로 재시도합니다.
    private func handleWatchWorkoutSessionFailure(session: WatchHeartRateWorkoutSession) {
        Self.diagnosticLogger.error(
            "HK session failure, restart attempt \(self.watchWorkoutSessionRestartAttempts + 1)"
        )
        guard watchWorkoutSession === session else { return }
        disableWatchBackgroundLocation()
        watchWorkoutSession = nil
        guard sessionData.state == .recording || sessionData.state == .paused else { return }
        guard watchWorkoutSessionRestartAttempts < Self.maxWatchWorkoutSessionRestartAttempts else { return }
        watchWorkoutSessionRestartAttempts += 1

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            guard self.sessionData.state == .recording || self.sessionData.state == .paused else { return }
            self.startWatchWorkoutSessionIfNeeded()
        }
    }

    /// 운동 빌더의 누적 활성 칼로리(HealthKit 실측)를 세션에 반영합니다.
    private func updateWatchActiveEnergy() {
        guard let kilocalories = watchWorkoutSession?.activeEnergyKilocalories else { return }
        if kilocalories > (sessionData.activeEnergyKilocalories ?? 0) {
            sessionData.activeEnergyKilocalories = kilocalories
        }
    }

    private func pauseWatchWorkoutSession() {
        watchWorkoutSession?.pause()
    }

    private func resumeWatchWorkoutSession() {
        guard sessionData.state == .recording else { return }
        if watchWorkoutSession == nil {
            startWatchWorkoutSessionIfNeeded()
        } else {
            watchWorkoutSession?.resume()
        }
    }

    private func stopWatchWorkoutSession() {
        guard let session = watchWorkoutSession else { return }
        updateWatchActiveEnergy()
        disableWatchBackgroundLocation()
        watchWorkoutSession = nil
        Task {
            await session.end()
        }
    }

    /// 시스템 운동 세션 복구 시 기록 중이면 HKWorkoutSession을 다시 붙입니다.
    /// (`WatchHeartRateWorkoutSession.start`가 시스템의 활성 세션을 먼저 복구하고, 없을 때만 새로 만듭니다.)
    func recoverActiveWatchWorkoutIfNeeded() async -> Bool {
        guard sessionData.state == .recording || sessionData.state == .paused else { return false }
        guard watchWorkoutSession == nil else { return true }

        startWatchWorkoutSessionIfNeeded()
        try? await Task.sleep(for: .milliseconds(300))
        return watchWorkoutSession?.hasStartedActivity == true
    }

    /// iPhone이 `startWatchApp(toHandle:)`로 워치 앱을 깨운 경우 — 최신 세션을 받아 HR 운동 세션을 시작합니다.
    func handleRemotelyLaunchedWorkout(configuration: HKWorkoutConfiguration) async {
        kickWatchConnectivityHandshake()

        // 동기화 지연 대비 — 잠깐 기다린 뒤에도 idle이면 한 번 더 요청합니다.
        if sessionData.state == .idle {
            try? await Task.sleep(for: .milliseconds(800))
            if sessionData.state == .idle {
                requestSessionSyncFromCounterpart()
                try? await Task.sleep(for: .milliseconds(800))
            }
        }

        if sessionData.state == .recording || sessionData.state == .paused {
            startWatchWorkoutSessionIfNeeded()
        }
    }
#endif

    // MARK: - 심박수 (iPhone)

#if os(iOS)
    private func startHeartRateCollectionIfNeeded() {
        guard shouldCollectHeartRateDuringWorkout else { return }
        guard sessionData.state == .recording else { return }
        guard HeartRateMonitor.canUseHealthKit else { return }
        guard shouldUseHealthKitHeartRateFallback() else { return }

        let startDate = sessionData.effectiveStartedAt ?? Date()
        HeartRateMonitor.shared.startCollecting(since: startDate) { [weak self] sample in
            Task { @MainActor in
                self?.appendHeartRateSample(sample)
            }
        }
    }

    /// iPhone에서 기록을 시작할 때 페어링된 Apple Watch 앱을 운동 세션으로 깨워 실시간 심박을 받습니다.
    /// 워치를 차고 있지 않거나 실패하면 HealthKit 패시브 심박 폴백이 그대로 동작합니다.
    private func startWatchWorkoutForLiveHeartRate() {
        guard shouldCollectHeartRateDuringWorkout else { return }
        guard isWatchCounterpartInstalled else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard !isLaunchingWatchWorkout else { return }
        isLaunchingWatchWorkout = true

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .hiking
        configuration.locationType = .outdoor

        let healthStore = watchWorkoutLauncherHealthStore ?? HKHealthStore()
        watchWorkoutLauncherHealthStore = healthStore

        Task { [weak self] in
            // startWatchApp은 워크아웃 공유 권한이 있어야 동작합니다.
            try? await healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                healthStore.startWatchApp(with: configuration) { _, _ in
                    continuation.resume()
                }
            }
            await MainActor.run { self?.isLaunchingWatchWorkout = false }
        }
    }

    private func shouldUseHealthKitHeartRateFallback() -> Bool {
        guard isWatchCounterpartInstalled else { return true }
        guard let last = sessionData.heartRateSamples.last else { return true }
        // Watch에서 WC로 최근 샘플이 오면 HealthKit 중복 수집을 줄입니다.
        return Date().timeIntervalSince(last.timestamp) > 12
    }

    private func pauseHeartRateCollection() {
        stopHeartRateCollection()
    }

    private func resumeHeartRateCollection() {
        guard shouldCollectHeartRateDuringWorkout else { return }
        guard sessionData.state == .recording else { return }
        startHeartRateCollectionIfNeeded()
    }

    private func stopHeartRateCollection() {
        HeartRateMonitor.shared.stopCollecting()
    }
#endif

    // MARK: - 걸음수(Core Motion)

    /// 기록 기기(위치 생산자)에서만 시작합니다 — 실시간 누적을 sessionData에 반영합니다.
    private func startStepCountingIfNeeded() {
        guard isLocationProducer else { return }
        guard StepCounter.isStepCountingAvailable else { return }
        let startDate = sessionData.effectiveStartedAt ?? workoutStartDate ?? Date()
        stepCounter.startLiveUpdates(from: startDate) { [weak self] steps in
            self?.applyLiveStepCount(steps)
        }
    }

    private func applyLiveStepCount(_ steps: Int) {
        guard sessionData.state == .recording else { return }
        // 실시간 누적은 단조 증가만 반영합니다.
        if steps <= (sessionData.stepCount ?? 0) { return }
        sessionData.stepCount = steps
        sessionData.lastUpdated = Date()
    }

    /// 종료 시점에 시작~종료 구간을 정밀 조회해 요약·백업에 반영합니다.
    private func finalizeStepCount() {
        guard isLocationProducer else { return }
        guard StepCounter.isStepCountingAvailable else { return }
        guard
            let startDate = summarySession?.effectiveStartedAt
                ?? sessionData.effectiveStartedAt
                ?? workoutStartDate
        else { return }
        let endDate = summarySession?.lastUpdated ?? sessionData.lastUpdated
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let steps = await self.stepCounter.queryStepCount(from: startDate, to: endDate) else { return }
            if self.isAwaitingSummaryConfirmation, var summary = self.summarySession {
                if steps >= (summary.stepCount ?? 0) {
                    summary.stepCount = steps
                    self.summarySession = summary
                }
                self.saveSummaryPendingBackup(summary)
                return
            }
            if steps >= (self.sessionData.stepCount ?? 0) {
                self.sessionData.stepCount = steps
            }
            self.saveLiveSessionBackupIfNeeded(force: true)
        }
    }

    // MARK: - 칼로리

    /// 워치 HealthKit 실측 활성 칼로리가 없을 때만(아이폰 단독) 추정값으로 채웁니다.
    private func finalizeActiveEnergyEstimateIfNeeded() {
        guard isLocationProducer else { return }
        if let measured = sessionData.activeEnergyKilocalories, measured > 0 { return }
        let estimate = CalorieEstimator.estimateActiveKilocalories(
            distanceMeters: sessionData.totalDistance,
            elevationGainMeters: sessionData.elevationGainMeters ?? sessionData.cumulativeElevationGain,
            durationSeconds: sessionData.elapsedTime,
            bodyMassKilograms: BodyMetricsPreferences.effectiveBodyMassKilograms
        )
        guard estimate > 0 else { return }
        sessionData.activeEnergyKilocalories = estimate
    }

    private func appendHeartRateSample(_ sample: HikingHeartRateSample) {
        guard sessionData.state == .recording else { return }

        if sessionData.heartRateSamples.contains(where: { $0.id == sample.id }) {
            sessionData.currentHeartRate = sample.bpm
            sessionData.lastUpdated = Date()
            return
        }

        sessionData.heartRateSamples.append(sample)
        sessionData.currentHeartRate = sample.bpm
        sessionData.lastUpdated = Date()

#if os(iOS)
        if !shouldUseHealthKitHeartRateFallback() {
            stopHeartRateCollection()
        }
#endif

        publishHeartRateSnapshotIfNeeded()
#if os(watchOS)
        sendHeartRateSample(sample)
#endif
    }

    private func publishHeartRateSnapshotIfNeeded() {
#if os(watchOS)
        let now = Date()
        if let lastPublished = lastHeartRateSnapshotPublishedAt,
           now.timeIntervalSince(lastPublished) < Self.heartRateSnapshotMinInterval {
            return
        }
        lastHeartRateSnapshotPublishedAt = now
#endif
        publishSessionSnapshot()
    }

    private func handleRemoteCommand(_ command: HikingSessionCommand) {
        // 로컬에서 요약 검토 중이면 상대 기기의 명령으로 기록을 다시 켜지 않습니다.
        if isAwaitingSummaryConfirmation, command != .discardRecording { return }

        isApplyingRemoteUpdate = true
        defer { isApplyingRemoteUpdate = false }

        switch command {
        case .startRecording:
            if sessionData.state == .idle {
                beginWorkout(syncRemote: false, asLocationProducer: false)
            } else if sessionData.state == .paused {
                setResumed(syncRemote: false)
            }
        case .pauseRecording:
            if sessionData.state == .recording {
                setPaused(syncRemote: false)
            }
        case .resumeRecording:
            if sessionData.state == .paused {
                setResumed(syncRemote: false)
            }
        case .stopRecording:
            if sessionData.state != .idle {
                setEnded(syncRemote: false)
            }
        case .discardRecording:
            isAwaitingSummaryConfirmation = false
            summarySession = nil
            if sessionData.state != .idle {
                persistDismissedSessionID(sessionData.sessionID)
                stopWorkoutTracking()
                resetSessionToIdle()
            }
        case .requestSync:
            publishSessionSnapshot()
        case .startLocationAssist:
#if os(watchOS)
            startLocationAssistCollection()
#endif
        case .stopLocationAssist:
#if os(watchOS)
            stopLocationAssistCollection()
#endif
        case .phoneTookOverRecording:
#if os(watchOS)
            adoptPhoneLocationProducerTakeover()
#endif
        }
    }

    /// 로컬 종료·기록 중 상태를 상대 기기의 오래된 스냅샷이 덮어쓰지 않도록 합니다.
    private func shouldIgnoreStaleRemoteSession(_ remote: HikingSessionData) -> Bool {
        if let dismissedSessionID,
           remote.sessionID == dismissedSessionID,
           remote.state != .idle {
            return true
        }

        guard isLocationProducer else { return false }
        switch sessionData.state {
        case .recording, .paused:
            if remote.sessionID != sessionData.sessionID { return true }
            if remote.state == .idle { return true }
            return false
        case .idle:
            if remote.state != .idle {
                let age = Date().timeIntervalSince(remote.lastUpdated)
                if age > Self.staleRemoteSessionMaxAge { return true }
            }
            return false
        }
    }

    /// iPhone이 idle일 때 Watch 캐시 스냅샷만으로 기록 UI가 켜지지 않도록 합니다.
    private func shouldAdoptRemoteWorkoutWhileIdle(_ remote: HikingSessionData) -> Bool {
#if os(iOS)
        guard sessionData.state == .idle else { return true }
        guard !isAwaitingSummaryConfirmation else { return false }
        guard remote.state == .recording || remote.state == .paused else { return true }
        guard isWatchConnectivitySupported, isWatchCounterpartInstalled else { return false }
        if let dismissedSessionID, remote.sessionID == dismissedSessionID {
            return false
        }

        let age = Date().timeIntervalSince(remote.lastUpdated)
        if isWatchReachable {
            return age <= Self.idleRemoteAdoptionMaxAge
        }
        if isWatchActivelyLinked {
            return age <= Self.idleRemoteAdoptionMaxAge
        }
        return false
#else
        return true
#endif
    }

    private func adoptRemoteRoleIfNeeded(wasIdle: Bool) {
        guard wasIdle else { return }
        switch sessionData.state {
        case .recording, .paused:
            isLocationProducer = false
        case .idle:
            break
        }
    }

    private func mergeFinalSessionFromRemote(_ remote: HikingSessionData) {
        guard sessionData.state != .idle else { return }
        guard remote.sessionID == sessionData.sessionID else { return }

        // 마킹을 먼저 병합 — 로컬 마킹에 재개 시각이 비어 있으면 재개 이후 포인트가
        // '일시정지 구간'으로 오인되어 병합에서 전부 걸러집니다.
        mergeRemoteSegmentBreaks(remote.segmentBreaks)
        mergeRemotePoints(remote.points)
        mergeRemotePhotos(remote.photos)
        sessionData.elapsedTime = max(sessionData.elapsedTime, remote.elapsedTime)
        if remote.lastUpdated > sessionData.lastUpdated {
            sessionData.lastUpdated = remote.lastUpdated
        }
        if let remoteStartedAt = remote.startedAt {
            sessionData.startedAt = remoteStartedAt
        }
        let reconciledDistance = max(sessionData.totalDistance, remote.totalDistance)
        if reconciledDistance > sessionData.totalDistance {
            sessionData.totalDistance = reconciledDistance
        }
        mergeRemoteHeartRateSamples(remote.heartRateSamples)
        if let remoteHeartRate = remote.currentHeartRate {
            sessionData.currentHeartRate = remoteHeartRate
        }
        if let remoteSteps = remote.stepCount {
            sessionData.stepCount = max(sessionData.stepCount ?? 0, remoteSteps)
        }
        if let remoteEnergy = remote.activeEnergyKilocalories {
            sessionData.activeEnergyKilocalories = max(sessionData.activeEnergyKilocalories ?? 0, remoteEnergy)
        }
    }

    private func applyRemoteSession(_ remote: HikingSessionData, mergePoints: Bool) {
        // 로컬 요약 검토 중에는 상대 기기 스냅샷으로 기록을 되살리지 않습니다.
        if isAwaitingSummaryConfirmation { return }

        isApplyingRemoteUpdate = true
        defer { isApplyingRemoteUpdate = false }

        if shouldIgnoreStaleRemoteSession(remote) {
            return
        }

#if os(iOS)
        if isPhoneRecordingFailoverActive,
           remote.sessionID == sessionData.sessionID,
           sessionData.state != .idle {
            mergeRemoteSegmentBreaks(remote.segmentBreaks)
            if mergePoints {
                mergeRemotePoints(remote.points)
                mergeRemotePhotos(remote.photos)
            }
            mergeRemoteHeartRateSamples(remote.heartRateSamples)
            if let remoteHeartRate = remote.currentHeartRate {
                sessionData.currentHeartRate = remoteHeartRate
            }
            if let remoteSteps = remote.stepCount {
                sessionData.stepCount = max(sessionData.stepCount ?? 0, remoteSteps)
            }
            if let remoteEnergy = remote.activeEnergyKilocalories {
                sessionData.activeEnergyKilocalories = max(
                    sessionData.activeEnergyKilocalories ?? 0,
                    remoteEnergy
                )
            }
            return
        }
#endif

        if remote.state == .idle,
           sessionData.state != .idle,
           remote.sessionID == sessionData.sessionID {
            mergeFinalSessionFromRemote(remote)
            setEnded(syncRemote: false)
            return
        }

        if !shouldAdoptRemoteWorkoutWhileIdle(remote) {
            return
        }

        guard remote.lastUpdated >= sessionData.lastUpdated
            || remote.sessionID != sessionData.sessionID
        else { return }

        let wasIdle = sessionData.state == .idle

        if remote.sessionID != sessionData.sessionID {
            sessionData = remote
            workoutStartDate = remote.effectiveStartedAt
            liveDistanceAnchor = HikingSessionMetrics.horizontalDistanceWithAnchor(from: remote.points).anchor
            adoptRemoteRoleIfNeeded(wasIdle: wasIdle)
            syncLocalTrackingToState()
            return
        }

        sessionData.state = remote.state
        if let remoteStartedAt = remote.startedAt {
            sessionData.startedAt = remoteStartedAt
        }
        sessionData.elapsedTime = remote.elapsedTime
        sessionData.currentPace = remote.currentPace
        sessionData.currentAltitude = remote.currentAltitude
        sessionData.lastUpdated = remote.lastUpdated

        // 마킹을 포인트보다 먼저 병합 — 재개 시각이 없는 마킹이 남아 있으면 재개 이후
        // 포인트가 '일시정지 구간'으로 오인되어 걸러집니다.
        mergeRemoteSegmentBreaks(remote.segmentBreaks)

        if mergePoints {
            mergeRemotePoints(remote.points)
            mergeRemotePhotos(remote.photos)
        } else {
            sessionData.totalDistance = remote.totalDistance
            sessionData.photos = remote.photos
        }

        mergeRemoteHeartRateSamples(remote.heartRateSamples)
        if let remoteHeartRate = remote.currentHeartRate {
            sessionData.currentHeartRate = remoteHeartRate
        }
        if let remoteSteps = remote.stepCount {
            sessionData.stepCount = max(sessionData.stepCount ?? 0, remoteSteps)
        }
        if let remoteEnergy = remote.activeEnergyKilocalories {
            sessionData.activeEnergyKilocalories = max(sessionData.activeEnergyKilocalories ?? 0, remoteEnergy)
        }

#if os(iOS)
        if !shouldUseHealthKitHeartRateFallback() {
            stopHeartRateCollection()
        }
#endif

        if workoutStartDate == nil {
            workoutStartDate = sessionData.effectiveStartedAt
        }

        adoptRemoteRoleIfNeeded(wasIdle: wasIdle)
        syncLocalTrackingToState()
    }

    /// 원격 스냅샷의 일시정지/재개 마킹을 id 기준으로 합치고, 재개 좌표가 뒤늦게 와도 보강합니다.
    private func mergeRemoteSegmentBreaks(_ incoming: [HikingSegmentBreak]?) {
        guard let incoming, !incoming.isEmpty else { return }
        var byID = Dictionary(
            (sessionData.segmentBreaks ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        for remoteBreak in incoming {
            if var existing = byID[remoteBreak.id] {
                var changed = false
                if existing.resumeLatitude == nil, let latitude = remoteBreak.resumeLatitude {
                    existing.resumeLatitude = latitude
                    existing.resumeLongitude = remoteBreak.resumeLongitude
                    changed = true
                }
                // 좌표 없이 재개 시각만 먼저 닫힌 경우에도 반영합니다.
                if existing.resumeTime == nil, let resumeTime = remoteBreak.resumeTime {
                    existing.resumeTime = resumeTime
                    changed = true
                }
                if changed {
                    byID[remoteBreak.id] = existing
                }
            } else {
                byID[remoteBreak.id] = remoteBreak
            }
        }
        sessionData.segmentBreaks = byID.values.sorted { $0.pauseTime < $1.pauseTime }
    }

    private func mergeRemotePoints(_ incoming: [HikingPoint]) {
        let incoming = remotePointsAcceptedForMerge(incoming)
        guard !incoming.isEmpty else { return }
        var merged = sessionData.points
        let existingIDs = Set(merged.map(\.id))
        for point in incoming where !existingIDs.contains(point.id) {
            guard shouldAcceptGPSPoint(at: point.timestamp) else { continue }
            merged.append(point)
        }
        merged.sort { $0.timestamp < $1.timestamp }
        sessionData.points = merged
        let recomputed = HikingSessionMetrics.horizontalDistanceWithAnchor(from: merged)
        sessionData.totalDistance = max(sessionData.totalDistance, recomputed.total)
        liveDistanceAnchor = recomputed.anchor
    }

    /// 워치가 꺼진 뒤 iPhone이 이어받은 구간은 워치 GPS를 다시 넣지 않습니다.
    private func remotePointsAcceptedForMerge(_ incoming: [HikingPoint]) -> [HikingPoint] {
#if os(iOS)
        guard isPhoneRecordingFailoverActive, let cutoff = phoneRecordingFailoverAt else {
            return incoming
        }
        return incoming.filter { $0.timestamp <= cutoff }
#else
        return incoming
#endif
    }

    private func mergeRemotePhotos(_ incoming: [HikingTrailPhoto]) {
        guard !incoming.isEmpty else { return }
        var merged = sessionData.photos
        let existingIDs = Set(merged.map(\.id))
        for photo in incoming where !existingIDs.contains(photo.id) {
            merged.append(photo)
        }
        merged.sort { $0.timestamp < $1.timestamp }
        sessionData.photos = merged
    }

    private func mergeRemoteHeartRateSamples(_ incoming: [HikingHeartRateSample]) {
        guard !incoming.isEmpty else { return }
        var merged = sessionData.heartRateSamples
        let existingIDs = Set(merged.map(\.id))
        for sample in incoming where !existingIDs.contains(sample.id) {
            merged.append(sample)
        }
        merged.sort { $0.timestamp < $1.timestamp }
        sessionData.heartRateSamples = merged
    }

    private func appendRemotePoint(_ point: HikingPoint) {
        guard !isAwaitingSummaryConfirmation else { return }
        guard sessionData.state == .recording else { return }
        guard shouldAcceptGPSPoint(at: point.timestamp) else { return }

        if isLocationProducer {
#if os(iOS)
            // 워치 GPS 보조 포인트 — 로컬 GPS 품질 저하 중에만, 마지막 저장 포인트 이후의
            // 시간순 포인트만 실시간 수용합니다(순서 뒤바뀐 포인트는 종료 병합이 처리).
            guard isWatchLocationAssistActive else { return }
            if let last = sessionData.points.last, point.timestamp <= last.timestamp { return }
#else
            return
#endif
        }
        guard !sessionData.points.contains(where: { $0.id == point.id }) else { return }

        accumulateLiveDistance(to: point)
        sessionData.points.append(point)
        sessionData.currentAltitude = point.altitude
        sessionData.lastUpdated = Date()
        saveLiveSessionBackupIfNeeded()
    }

    private func syncLocalTrackingToState() {
        switch sessionData.state {
        case .idle:
            if isLocationProducer {
                locationManager.stopUpdatingLocation()
            }
            stopElapsedTimer()
#if os(iOS)
            backgroundActivitySession?.invalidate()
            backgroundActivitySession = nil
            disableBackgroundLocation()
            stopHeartRateCollection()
            isMapLocationTrackingActive = false
            prepareDashboardMapLocation()
#endif
#if os(watchOS)
            isAssistingLocation = false
            if !isLocationProducer {
                locationManager.stopUpdatingLocation()
            }
            stopWatchWorkoutSession()
            disableWatchBackgroundLocation()
#endif
        case .recording:
            if isLocationProducer {
                // 앱 재실행·상태 복구 시에도 기록용 설정(Best 정확도)을 다시 적용합니다.
                restartLocationTrackingForActiveWorkout()
            } else {
#if os(watchOS)
                // GPS 보조 수집 중에는 위치 업데이트를 유지합니다.
                if !isAssistingLocation {
                    locationManager.stopUpdatingLocation()
                }
#else
                locationManager.stopUpdatingLocation()
#endif
            }
            startElapsedTimer()
#if os(iOS)
            enableBackgroundLocationIfAuthorized()
            startHeartRateCollectionIfNeeded()
            startiPhoneWorkoutKeepAliveIfNeeded()
            updateScreenSleepPrevention()
#endif
#if os(watchOS)
            startWatchWorkoutSessionIfNeeded()
#endif
        case .paused:
            if isLocationProducer {
                locationManager.stopUpdatingLocation()
            }
            stopElapsedTimer()
            stepCounter.stopLiveUpdates()
#if os(iOS)
            pauseiPhoneWorkoutKeepAlive()
            updateScreenSleepPrevention()
#endif
#if os(watchOS)
            stopLocationAssistCollection()
            pauseWatchWorkoutSession()
#endif
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WorkoutManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
#if os(iOS)
            handleAuthorizationStatusChange()
#else
            // 기록 시작 시점에 권한이 .notDetermined여서 GPS를 못 켰던 경우 — 허용 즉시 추적을 시작합니다.
            if sessionData.state == .recording, canRecordWithCurrentLocationAuthorization {
                restartLocationTrackingForActiveWorkout()
            }
#endif
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !locations.isEmpty else { return }
        Task { @MainActor in
#if os(iOS)
            if isAwaitingPhotoLocation {
                let candidates = locations.sorted { $0.timestamp < $1.timestamp }
                if let location = candidates.last(where: {
                    $0.horizontalAccuracy > 0 && $0.horizontalAccuracy <= 35
                }) {
                    finishPhotoLocationRequest(returning: location)
                    return
                }
            }
#endif
#if os(iOS)
            if sessionData.state == .idle, isMapLocationTrackingActive,
               let location = locations.sorted(by: { $0.timestamp < $1.timestamp }).last,
               location.horizontalAccuracy > 0 {
                publishMapLocationIfNeeded(location)
            }
#endif
            if pauseActivityMonitorActive, sessionData.state == .paused, isLocationProducer {
                for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
                    ingestPauseActivityLocation(location)
                }
            }
            for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
                ingestLocation(location)
            }
#if os(iOS)
            if let latest = locations.max(by: { $0.timestamp < $1.timestamp }) {
                trackRawGPSQualityForAssist(latest)
            }
#endif
#if os(watchOS)
            if isAssistingLocation, !isLocationProducer, sessionData.state == .recording {
                for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
                    ingestAssistLocation(location)
                }
            }
#endif
        }
    }

#if os(iOS)
    nonisolated func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor in
            handleLocationManagerDidPauseLocationUpdates()
        }
    }
#endif

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
#if os(iOS)
            if isAwaitingPhotoLocation {
                finishPhotoLocationRequest(returning: nil)
            }
#endif
        }
    }
}

// MARK: - WCSessionDelegate

extension WorkoutManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            kickWatchConnectivityHandshake()
            applyReceivedApplicationContextIfAvailable(session)
        }
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            refreshWatchCounterpartState(session)
            session.activate()
        }
    }
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            refreshWatchCounterpartState(session)
        }
    }

#if os(iOS)
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            refreshWatchCounterpartState(session)
        }
    }
#endif

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            markWatchSyncActivity()
            guard let snapshot = HikingSessionData(applicationContext: applicationContext) else { return }
            applyRemoteSession(snapshot, mergePoints: true)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            markWatchSyncActivity()
            if let command = HikingSessionCommand(dictionary: message) {
                handleRemoteCommand(command)
                return
            }
            if let point = HikingPoint(message: message) {
                appendRemotePoint(point)
                return
            }
            if let sample = HikingHeartRateSample(message: message) {
                appendHeartRateSample(sample)
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            markWatchSyncActivity()
            if let command = HikingSessionCommand(dictionary: message) {
                handleRemoteCommand(command)
                if command == .requestSync, let data = try? sessionData.encoded() {
                    replyHandler([HikingConnectivityKeys.sessionSnapshot: data])
                } else {
                    replyHandler([:])
                }
                return
            }
            if let point = HikingPoint(message: message) {
                appendRemotePoint(point)
                replyHandler([:])
                return
            }
            if let sample = HikingHeartRateSample(message: message) {
                appendHeartRateSample(sample)
            }
            replyHandler([:])
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // 델리게이트 반환 후 시스템이 파일을 삭제하므로 동기적으로 읽어둡니다.
        guard let data = try? Data(contentsOf: file.fileURL) else { return }
        Task { @MainActor in
            self.markWatchSyncActivity()
            if self.sessionData.state != .idle,
               let snapshot = try? HikingSessionData.decoded(from: data),
               snapshot.sessionID == self.sessionData.sessionID {
                self.handleReceivedFullSessionTransfer(snapshot)
                return
            }
#if os(iOS)
            WatchRecordInbox.enqueueEncodedSession(data)
#endif
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        guard error == nil else { return }
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            markWatchSyncActivity()
            if let command = HikingSessionCommand(dictionary: userInfo), command == .stopRecording {
#if os(iOS)
                handleReceivedStopRecordingUserInfo(userInfo)
#else
                if let snapshot = HikingSessionData(userInfo: userInfo) {
                    mergeFinalSessionFromRemote(snapshot)
                }
                handleRemoteCommand(.stopRecording)
#endif
                return
            }
            guard let snapshot = HikingSessionData(userInfo: userInfo) else { return }
            applyRemoteSession(snapshot, mergePoints: true)
        }
    }
}
