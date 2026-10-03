//
//  sansanWatchApp.swift
//  sansan Watch App
//

import SwiftUI

@main
struct sansanWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate
    @StateObject private var workoutManager = WorkoutManager.shared

    var body: some Scene {
        WindowGroup {
            WatchWorkoutView()
                .environmentObject(workoutManager)
        }
    }
}
