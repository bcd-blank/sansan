//
//  WatchHeartRateWorkoutSession.swift
//  Shared
//
//  Apple Watch — 등산 기록 중 HKWorkoutSession (화면 꺼짐·손목 내림 후에도 앱·센서 유지).
//  Nike Running과 같이 HKWorkoutSession + HKLiveWorkoutBuilder로 백그라운드 심박을 수집합니다.
//

#if os(watchOS)

import Foundation
import HealthKit
import os

/// 앱 세션당 HealthKit 권한 요청을 한 번만 수행합니다.
private enum WatchHealthKitAuthorization {
    private actor Gate {
        private var preparationTask: Task<Void, Never>?
        private var isPrepared = false

        func prepareIfNeeded() async {
            if isPrepared { return }
            if let preparationTask {
                await preparationTask.value
                return
            }

            let task = Task<Void, Never> {
                guard HKHealthStore.isHealthDataAvailable() else { return }
                guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
                var readTypes: Set<HKObjectType> = [heartRateType]
                if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                    readTypes.insert(energyType)
                }
                let healthStore = HKHealthStore()
                try? await healthStore.requestAuthorization(
                    toShare: [HKObjectType.workoutType()],
                    read: readTypes
                )
            }

            preparationTask = task
            await task.value
            preparationTask = nil
            isPrepared = true
        }
    }

    private static let gate = Gate()

    static func prepareIfNeeded() async {
        await gate.prepareIfNeeded()
    }
}

private struct WatchHeartRateSessionState: @unchecked Sendable {
    var session: HKWorkoutSession?
    var builder: HKLiveWorkoutBuilder?
    /// HKWorkoutSessionDelegate가 전달한 실제 세션 상태 — `.running` 도달 전에는 백그라운드 위치를 켜면 안 됩니다.
    var sessionRunState: HKWorkoutSessionState = .notStarted
}

/// NSObject delegate 콜백(nonisolated)과 async 메서드가 공유하는 스레드 안전 상태.
private final class WatchHeartRateSessionStateBox: @unchecked Sendable {
    nonisolated private let lock = OSAllocatedUnfairLock(initialState: WatchHeartRateSessionState())
    nonisolated(unsafe) private var onSample: ((HikingHeartRateSample) -> Void)?
    nonisolated(unsafe) private var onRunningStateChange: ((Bool) -> Void)?
    nonisolated(unsafe) private var onFailure: (() -> Void)?

    nonisolated var isRunning: Bool {
        lock.withLock {
            $0.session != nil && ($0.sessionRunState == .running || $0.sessionRunState == .paused)
        }
    }

    nonisolated var hasSession: Bool {
        lock.withLock { $0.session != nil }
    }

    nonisolated var builder: HKLiveWorkoutBuilder? {
        lock.withLock { $0.builder }
    }

    nonisolated func setOnSample(_ handler: @escaping (HikingHeartRateSample) -> Void) {
        onSample = handler
    }

    nonisolated func setOnRunningStateChange(_ handler: @escaping (Bool) -> Void) {
        onRunningStateChange = handler
    }

    nonisolated func setOnFailure(_ handler: @escaping () -> Void) {
        onFailure = handler
    }

    nonisolated func setSession(
        _ session: HKWorkoutSession,
        builder: HKLiveWorkoutBuilder,
        runState: HKWorkoutSessionState
    ) {
        lock.withLock {
            $0.session = session
            $0.builder = builder
            $0.sessionRunState = runState
        }
    }

    nonisolated func clearSession() {
        lock.withLock {
            $0.session = nil
            $0.builder = nil
            $0.sessionRunState = .notStarted
        }
    }

    nonisolated func updateSessionRunState(_ runState: HKWorkoutSessionState) {
        lock.withLock { $0.sessionRunState = runState }
    }

    nonisolated func takeActiveSession() -> (HKWorkoutSession, HKLiveWorkoutBuilder?)? {
        onSample = nil
        onRunningStateChange = nil
        onFailure = nil
        return lock.withLock { state -> (HKWorkoutSession, HKLiveWorkoutBuilder?)? in
            guard let activeSession = state.session else { return nil }
            let activeBuilder = state.builder
            state.session = nil
            state.builder = nil
            state.sessionRunState = .notStarted
            return (activeSession, activeBuilder)
        }
    }

    nonisolated func activeSession() -> HKWorkoutSession? {
        lock.withLock { $0.session }
    }

    nonisolated func consumeSampleHandler() -> ((HikingHeartRateSample) -> Void)? {
        onSample
    }

    nonisolated func consumeRunningStateHandler() -> ((Bool) -> Void)? {
        onRunningStateChange
    }

    nonisolated func consumeFailureHandler() -> (() -> Void)? {
        onFailure
    }
}

final class WatchHeartRateWorkoutSession: NSObject, @unchecked Sendable {
    /// NSObject 서브클래스는 MainActor로 추론될 수 있어, delegate·async 경로용 상태는 nonisolated로 둡니다.
    nonisolated private let stateBox = WatchHeartRateSessionStateBox()
    nonisolated private let healthStore = HKHealthStore()
    nonisolated fileprivate static let logger = Logger(
        subsystem: "com.jw.sansan.watchkitapp",
        category: "WatchHeartRateWorkoutSession"
    )

    /// delegate가 확인한 세션 상태가 실제 `.running`(또는 이후 `.paused`)일 때만 true —
    /// 그 전에 백그라운드 위치를 켜면 CoreLocation `stayUp` 단언으로 앱이 종료됩니다.
    nonisolated var hasStartedActivity: Bool {
        stateBox.isRunning
    }

    /// HKWorkoutSession 객체가 존재하는지(생성 실패·실패 정리 후에는 false).
    nonisolated var hasActiveSession: Bool {
        stateBox.hasSession
    }

    nonisolated static func prepareAuthorizationIfNeeded() async {
        await WatchHealthKitAuthorization.prepareIfNeeded()
    }

    func setOnSample(_ handler: @escaping (HikingHeartRateSample) -> Void) {
        stateBox.setOnSample(handler)
    }

    /// 세션이 실제 `.running`에 도달(또는 이탈)했을 때 MainActor에서 알립니다 — 백그라운드 위치 활성화 시점용.
    func setOnRunningStateChange(_ handler: @escaping @MainActor (Bool) -> Void) {
        stateBox.setOnRunningStateChange { isRunning in
            Task { @MainActor in
                handler(isRunning)
            }
        }
    }

    /// HKWorkoutSession이 시작 실패(didFailWithError)로 죽었을 때 MainActor에서 알립니다 — 재시도용.
    func setOnFailure(_ handler: @escaping @MainActor () -> Void) {
        stateBox.setOnFailure {
            Task { @MainActor in
                handler()
            }
        }
    }

    /// 운동 빌더가 수집한 누적 활성 칼로리(kcal). 세션이 없으면 nil.
    var activeEnergyKilocalories: Double? {
        guard
            let builder = stateBox.builder,
            let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            let statistics = builder.statistics(for: energyType),
            let sum = statistics.sumQuantity()
        else { return nil }
        let kilocalories = sum.doubleValue(for: .kilocalorie())
        return kilocalories > 0 ? kilocalories : nil
    }

    /// 기록 시작 전 권한을 미리 받아 두어 운동 시작과 동시에 센서를 켭니다.
    func prepareForWorkout() async {
        await Self.prepareAuthorizationIfNeeded()
    }

    nonisolated func start(at startDate: Date = Date()) async {
        guard !stateBox.hasSession else { return }

        Self.logger.notice("start: requesting HealthKit authorization")
        await Self.prepareAuthorizationIfNeeded()
        Self.logger.notice("start: authorization done, checking orphaned session")

        // 크래시·강제 종료 후 시스템에 활성 세션이 남아 있으면 새 세션을 만들지 않고 다시 붙습니다.
        // 활성 세션이 남은 채 새 HKWorkoutSession을 시작하면 조용히 실패해 심박·백그라운드 유지가 죽습니다.
        if await recoverSystemActiveSession() {
            Self.logger.notice("start: reattached to recovered active session")
            return
        }
        Self.logger.notice("start: creating new HKWorkoutSession")

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .hiking
        configuration.locationType = .outdoor

        let workoutSession: HKWorkoutSession
        let workoutBuilder: HKLiveWorkoutBuilder
        do {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutBuilder = workoutSession.associatedWorkoutBuilder()
            workoutBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            workoutSession.delegate = self
            workoutBuilder.delegate = self

            stateBox.setSession(workoutSession, builder: workoutBuilder, runState: workoutSession.state)
            workoutSession.startActivity(with: startDate)
        } catch {
            stateBox.clearSession()
            return
        }

        do {
            try await workoutBuilder.beginCollection(at: startDate)
            Self.logger.notice("start: beginCollection succeeded")
            Self.deliverMostRecentHeartRate(from: workoutBuilder, stateBox: stateBox)
        } catch {
            // 심박 수집 실패해도 HKWorkoutSession은 유지 — 손목 들기 시 앱이 다시 나타납니다.
            Self.logger.error(
                "start: beginCollection failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// 시스템에 남아 있는 활성 HKWorkoutSession을 찾아 세션·빌더에 다시 붙습니다.
    /// 복구된 빌더는 이미 수집 중이므로 `beginCollection`은 다시 호출하지 않습니다.
    nonisolated private func recoverSystemActiveSession() async -> Bool {
        return await withCheckedContinuation { continuation in
            healthStore.recoverActiveWorkoutSession { [weak self, healthStore] session, error in
                if let error {
                    Self.logger.error(
                        "recoverActiveWorkoutSession failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                guard let self, let workoutSession = session else {
                    continuation.resume(returning: false)
                    return
                }
                // 이미 끝난(비활성) 잔여 세션은 복구 대상이 아니지만, 시스템에 남아 있으면
                // 새 HKWorkoutSession 시작이 didFailWithError로 조용히 실패하므로 정리하고 넘어갑니다.
                guard workoutSession.state == .running || workoutSession.state == .paused else {
                    Self.logger.notice(
                        "Ending stale orphaned workout session (state: \(workoutSession.state.rawValue))"
                    )
                    workoutSession.end()
                    continuation.resume(returning: false)
                    return
                }
                guard !self.stateBox.hasSession else {
                    continuation.resume(returning: true)
                    return
                }

                let workoutBuilder = workoutSession.associatedWorkoutBuilder()
                workoutBuilder.dataSource = HKLiveWorkoutDataSource(
                    healthStore: healthStore,
                    workoutConfiguration: workoutSession.workoutConfiguration
                )
                workoutSession.delegate = self
                workoutBuilder.delegate = self
                self.stateBox.setSession(
                    workoutSession,
                    builder: workoutBuilder,
                    runState: workoutSession.state
                )

                if workoutSession.state == .running || workoutSession.state == .paused {
                    Self.notifyRunningStateChange(true, stateBox: self.stateBox)
                }
                Self.deliverMostRecentHeartRate(from: workoutBuilder, stateBox: self.stateBox)
                continuation.resume(returning: true)
            }
        }
    }

    func pause() {
        stateBox.activeSession()?.pause()
    }

    func resume() {
        stateBox.activeSession()?.resume()
    }

    nonisolated func end() async {
        guard let (activeSession, activeBuilder) = stateBox.takeActiveSession() else { return }

        let endDate = Date()
        activeSession.end()
        if let activeBuilder {
            do {
                try await activeBuilder.endCollection(at: endDate)
                try await activeBuilder.finishWorkout()
            } catch {
                // Watch 운동 세션 종료 실패는 기록 자체를 막지 않습니다.
            }
        }
    }

    nonisolated private static func deliver(
        _ sample: HikingHeartRateSample,
        stateBox: WatchHeartRateSessionStateBox
    ) {
        guard let handler = stateBox.consumeSampleHandler() else { return }
        Task { @MainActor in
            handler(sample)
        }
    }

    nonisolated fileprivate static func notifyRunningStateChange(
        _ isRunning: Bool,
        stateBox: WatchHeartRateSessionStateBox
    ) {
        stateBox.consumeRunningStateHandler()?(isRunning)
    }

    nonisolated private static func deliverMostRecentHeartRate(
        from builder: HKLiveWorkoutBuilder,
        stateBox: WatchHeartRateSessionStateBox
    ) {
        guard let sample = makeSample(from: builder) else { return }
        deliver(sample, stateBox: stateBox)
    }
}

extension WatchHeartRateWorkoutSession: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Self.logger.notice(
            "HKWorkoutSession state \(fromState.rawValue) -> \(toState.rawValue)"
        )
        let wasRunning = stateBox.isRunning
        stateBox.updateSessionRunState(toState)
        let isRunning = stateBox.isRunning
        if isRunning != wasRunning {
            Self.notifyRunningStateChange(isRunning, stateBox: stateBox)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Self.logger.error("HKWorkoutSession failed: \(error.localizedDescription, privacy: .public)")
        let wasRunning = stateBox.isRunning
        stateBox.clearSession()
        if wasRunning {
            Self.notifyRunningStateChange(false, stateBox: stateBox)
        }
        stateBox.consumeFailureHandler()?()
    }
}

extension WatchHeartRateWorkoutSession: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(heartRateType) else { return }

        guard let sample = Self.makeSample(from: workoutBuilder) else { return }
        Self.deliver(sample, stateBox: stateBox)
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated private static func makeSample(from builder: HKLiveWorkoutBuilder) -> HikingHeartRateSample? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let statistics = builder.statistics(for: heartRateType),
              let quantity = statistics.mostRecentQuantity() else {
            return nil
        }

        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
        let bpm = quantity.doubleValue(for: unit)
        guard bpm > 0 else { return nil }

        let timestamp = statistics.mostRecentQuantityDateInterval()?.end ?? Date()
        return HikingHeartRateSample(bpm: bpm, timestamp: timestamp)
    }
}

#endif
