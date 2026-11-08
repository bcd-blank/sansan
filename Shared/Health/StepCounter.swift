//
//  StepCounter.swift
//  Shared
//
//  Core Motion 만보계(CMPedometer) 래퍼 — 기록 구간의 걸음수를 실시간/사후로 수집합니다.
//  종료 시 CMPedometer 조회가 비거나 실패하면 HealthKit 걸음수 통계로 보강합니다.
//  iPhone·Apple Watch 모두 내장 만보계에서 동작하며, 기록을 수행하는 기기에서 수집합니다.
//  Xcode: Shared/Health 타겟 멤버십 → sansan, sansan Watch App
//

import CoreMotion
import Foundation
import HealthKit

@MainActor
final class StepCounter {
    /// 기기가 걸음수 측정을 지원하는지.
    static var isStepCountingAvailable: Bool {
        CMPedometer.isStepCountingAvailable()
    }

    private let pedometer = CMPedometer()
    private var isLive = false
    private var onUpdate: ((Int) -> Void)?
    private var healthStore: HKHealthStore?

    /// `startDate` 이후 누적 걸음수를 실시간으로 콜백 전달합니다.
    func startLiveUpdates(from startDate: Date, onUpdate: @escaping (Int) -> Void) {
        guard Self.isStepCountingAvailable else { return }
        stopLiveUpdates()
        self.onUpdate = onUpdate
        isLive = true
        pedometer.startUpdates(from: startDate) { [weak self] data, error in
            guard error == nil, let data else { return }
            let steps = data.numberOfSteps.intValue
            Task { @MainActor in
                self?.onUpdate?(steps)
            }
        }
    }

    func stopLiveUpdates() {
        guard isLive else { return }
        isLive = false
        pedometer.stopUpdates()
        onUpdate = nil
    }

    /// 종료 시점에 `[start, end]` 구간의 정확한 총 걸음수를 조회합니다(실시간 누적 보정용).
    /// CMPedometer → HealthKit 순으로 시도해, 워치 백그라운드에서 만보계 콜백이
    /// 비더라도 Health에 쌓인 걸음수를 살립니다.
    func queryStepCount(from startDate: Date, to endDate: Date) async -> Int? {
        guard endDate > startDate else { return nil }
        if let pedometerSteps = await queryPedometerStepCount(from: startDate, to: endDate),
           pedometerSteps > 0 {
            return pedometerSteps
        }
        if let healthSteps = await queryHealthKitStepCount(from: startDate, to: endDate),
           healthSteps > 0 {
            return healthSteps
        }
        // 둘 다 0·nil이면 pedometer 0을 우선(실제 0걸음과 구분 불가 시 nil 유지).
        return await queryPedometerStepCount(from: startDate, to: endDate)
    }

    private func queryPedometerStepCount(from startDate: Date, to endDate: Date) async -> Int? {
        guard Self.isStepCountingAvailable else { return nil }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            pedometer.queryPedometerData(from: startDate, to: endDate) { data, error in
                if let data, error == nil {
                    continuation.resume(returning: data.numberOfSteps.intValue)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func queryHealthKitStepCount(from startDate: Date, to endDate: Date) async -> Int? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let store = resolvedHealthStore()
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        return await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                guard error == nil,
                      let sum = statistics?.sumQuantity()
                else {
                    continuation.resume(returning: nil)
                    return
                }
                let steps = Int(sum.doubleValue(for: HKUnit.count()).rounded())
                continuation.resume(returning: max(0, steps))
            }
            store.execute(query)
        }
    }

    private func resolvedHealthStore() -> HKHealthStore {
        if let healthStore {
            return healthStore
        }
        let store = HKHealthStore()
        healthStore = store
        return store
    }
}
