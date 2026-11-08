//
//  PhoneWorkoutKeepAliveSession.swift
//  Shared
//
//  iPhone — 등산 기록 중 HKWorkoutSession으로 백그라운드 실행·GPS 유지.
//

#if os(iOS)

import Foundation
import HealthKit

@MainActor
final class PhoneWorkoutKeepAliveSession: NSObject {
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var didAuthorize = false

    func start(at startDate: Date) async {
        guard session == nil else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }

        if !didAuthorize {
            try? await healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
            didAuthorize = true
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .hiking
        configuration.locationType = .outdoor

        do {
            let workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutSession.delegate = self
            session = workoutSession
            workoutSession.startActivity(with: startDate)
        } catch {
            session = nil
        }
    }

    func pause() {
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    func end() async {
        guard let activeSession = session else { return }
        activeSession.end()
        session = nil
    }
}

extension PhoneWorkoutKeepAliveSession: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

#endif
