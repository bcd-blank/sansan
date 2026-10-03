//
//  LocationPermissionHandling.swift
//  Shared
//
//  기록 시작 전 위치 권한 안내 흐름.
//

import CoreLocation
import Foundation

enum LocationPermissionAlert: Identifiable, Equatable {
    case primer
    case denied
#if os(iOS)
    case alwaysRecommended
#endif

    var id: Self { self }
}

enum LocationPermissionHandling {
    /// 기록 시작 탭 — 안내가 필요하면 알림을 띄우고, 아니면 바로 시작합니다.
    static func handleWorkoutStartTap(
        workout: WorkoutManager,
        alert: inout LocationPermissionAlert?,
        pendingStartWorkout: inout Bool
    ) {
        if workout.needsLocationPermissionExplanation {
            pendingStartWorkout = true
            alert = .primer
            return
        }
        if workout.isLocationPermissionBlocked {
            pendingStartWorkout = false
            alert = .denied
            return
        }
        pendingStartWorkout = false
        workout.startWorkout()
    }

    /// 시스템 권한 대화상자 결과에 따라 대기 중인 기록을 시작하거나 거부 안내를 띄웁니다.
    static func handleAuthorizationChange(
        workout: WorkoutManager,
        oldStatus: CLAuthorizationStatus,
        newStatus: CLAuthorizationStatus,
        pendingStartWorkout: inout Bool,
        alert: inout LocationPermissionAlert?
    ) {
        if pendingStartWorkout {
            if workout.canRecordWithCurrentLocationAuthorization {
                pendingStartWorkout = false
                workout.startWorkout()
#if os(iOS)
                if newStatus == .authorizedWhenInUse {
                    alert = .alwaysRecommended
                }
#endif
            } else if workout.isLocationPermissionBlocked {
                pendingStartWorkout = false
                alert = .denied
            }
            return
        }

#if os(iOS)
        if oldStatus == .notDetermined,
           newStatus == .authorizedWhenInUse,
           workout.sessionData.state == .recording {
            alert = .alwaysRecommended
        }
#endif
    }

    /// 안내 후 시스템 위치 권한 요청.
    static func confirmLocationPrimer(workout: WorkoutManager) {
        workout.requestWhenInUseLocationAuthorization()
    }
}
