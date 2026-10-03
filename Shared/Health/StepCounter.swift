//
//  StepCounter.swift
//  Shared
//
//  Core Motion 만보계(CMPedometer) 래퍼 — 기록 구간의 걸음수를 실시간/사후로 수집합니다.
//  iPhone·Apple Watch 모두 내장 만보계에서 동작하며, 기록을 수행하는 기기에서 수집합니다.
//  Xcode: Shared/Health 타겟 멤버십 → sansan, sansan Watch App
//

import CoreMotion
import Foundation

@MainActor
final class StepCounter {
    /// 기기가 걸음수 측정을 지원하는지.
    static var isStepCountingAvailable: Bool {
        CMPedometer.isStepCountingAvailable()
    }

    private let pedometer = CMPedometer()
    private var isLive = false
    private var onUpdate: ((Int) -> Void)?

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
    func queryStepCount(from startDate: Date, to endDate: Date) async -> Int? {
        guard Self.isStepCountingAvailable else { return nil }
        guard endDate > startDate else { return nil }
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
}
