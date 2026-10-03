//
//  HeartRateMonitor.swift
//  Shared
//
//  iPhone — HealthKit 심박수 실시간 수집(Apple Watch · 건강 앱 연동).
//  Nike Run Club과 같이 HKWorkoutSession이 HealthKit에 쓴 샘플을 즉시 관찰합니다.
//

#if os(iOS)

import Foundation
import HealthKit

@MainActor
final class HeartRateMonitor {
    static let shared = HeartRateMonitor()

    private var healthStore: HKHealthStore?
    private var anchoredQuery: HKAnchoredObjectQuery?
    private var observerQuery: HKObserverQuery?
    private var queryAnchor: HKQueryAnchor?
    private var collectingSince: Date?
    private var onSample: ((HikingHeartRateSample) -> Void)?

    private init() {}

    static var canUseHealthKit: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var isHealthDataAvailable: Bool {
        Self.canUseHealthKit
    }

    func requestAuthorization() async throws {
        guard let healthStore = resolvedHealthStore() else { return }
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        try await healthStore.requestAuthorization(toShare: [], read: [heartRateType])
    }

    /// 기록 시작 전 미리 권한을 요청해 운동 시작 직후 지연을 줄입니다.
    func prepareForWorkout() async {
        try? await requestAuthorization()
    }

    func startCollecting(since startDate: Date, onSample: @escaping (HikingHeartRateSample) -> Void) {
        stopCollecting()
        guard let healthStore = resolvedHealthStore() else { return }
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }

        queryAnchor = nil
        collectingSince = startDate
        self.onSample = onSample

        let predicate = Self.samplesPredicate(since: startDate)

        fetchRecentSamples(healthStore: healthStore, type: heartRateType, predicate: predicate)

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { _, samples, _, newAnchor, error in
            guard error == nil else { return }
            let anchor = newAnchor
            let sampleList = samples
            Task { @MainActor in
                HeartRateMonitor.shared.receiveQueryResults(anchor: anchor, samples: sampleList)
            }
        }

        query.updateHandler = { _, samples, _, newAnchor, error in
            guard error == nil else { return }
            let anchor = newAnchor
            let sampleList = samples
            Task { @MainActor in
                HeartRateMonitor.shared.receiveQueryResults(anchor: anchor, samples: sampleList)
            }
        }

        anchoredQuery = query
        healthStore.execute(query)

        let observer = HKObserverQuery(sampleType: heartRateType, predicate: predicate) { _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            Task { @MainActor in
                HeartRateMonitor.shared.refreshFromObserver()
                completionHandler()
            }
        }
        observerQuery = observer
        healthStore.execute(observer)
        healthStore.enableBackgroundDelivery(for: heartRateType, frequency: .immediate) { _, _ in }
    }

    func stopCollecting() {
        if let anchoredQuery, let healthStore = resolvedHealthStore() {
            healthStore.stop(anchoredQuery)
        }
        if let observerQuery, let healthStore = resolvedHealthStore() {
            healthStore.stop(observerQuery)
        }
        anchoredQuery = nil
        observerQuery = nil
        collectingSince = nil
        onSample = nil
    }

    private func refreshFromObserver() {
        guard let healthStore = resolvedHealthStore(),
              let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let startDate = collectingSince else { return }

        fetchRecentSamples(
            healthStore: healthStore,
            type: heartRateType,
            predicate: Self.samplesPredicate(since: startDate)
        )
    }

    private func fetchRecentSamples(
        healthStore: HKHealthStore,
        type: HKQuantityType,
        predicate: NSPredicate
    ) {
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, samples, _ in
            Task { @MainActor in
                HeartRateMonitor.shared.deliver(samples)
            }
        }
        healthStore.execute(query)
    }

    private static func samplesPredicate(since startDate: Date) -> NSPredicate {
        HKQuery.predicateForSamples(
            withStart: startDate,
            end: nil,
            options: .strictStartDate
        )
    }

    private func resolvedHealthStore() -> HKHealthStore? {
        guard Self.canUseHealthKit else { return nil }
        if let healthStore {
            return healthStore
        }
        let store = HKHealthStore()
        healthStore = store
        return store
    }

    private func receiveQueryResults(anchor: HKQueryAnchor?, samples: [HKSample]?) {
        queryAnchor = anchor
        deliver(samples)
    }

    private func deliver(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample] else { return }
        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())

        for sample in quantitySamples {
            let bpm = sample.quantity.doubleValue(for: unit)
            guard bpm > 0 else { continue }
            let hikingSample = HikingHeartRateSample(
                id: sample.uuid,
                bpm: bpm,
                timestamp: sample.startDate
            )
            onSample?(hikingSample)
        }
    }
}

#endif
