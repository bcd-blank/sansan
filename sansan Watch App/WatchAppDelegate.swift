//
//  WatchAppDelegate.swift
//  sansan Watch App
//

import HealthKit
import WatchKit

@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        Task {
            _ = await WorkoutManager.shared.recoverActiveWatchWorkoutIfNeeded()
        }
    }

    /// iPhone이 `startWatchApp(toHandle:)`로 워치 앱을 깨운 경우 시스템이 호출합니다.
    nonisolated func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await WorkoutManager.shared.handleRemotelyLaunchedWorkout(configuration: workoutConfiguration)
        }
    }
}
