//
//  LocationPermissionAlertModifier.swift
//  Shared
//
//  위치 권한 안내 알림.
//

import CoreLocation
import SwiftUI

struct LocationPermissionAlertModifier: ViewModifier {
    var workout: WorkoutManager
#if os(iOS)
    @ObservedObject private var chrome = WorkoutChromeStateObserver.shared
#endif
    @Binding var alert: LocationPermissionAlert?
    @Binding var pendingStartWorkout: Bool

    func body(content: Content) -> some View {
        content
#if os(iOS)
            .onChange(of: chrome.authorizationStatus) { oldStatus, newStatus in
                handleAuthorizationChange(from: oldStatus, to: newStatus)
            }
#else
            .onChange(of: workout.authorizationStatus) { oldStatus, newStatus in
                handleAuthorizationChange(from: oldStatus, to: newStatus)
            }
#endif
            .alert(item: $alert) { kind in
                alertContent(for: kind)
            }
    }

    private func handleAuthorizationChange(
        from oldStatus: CLAuthorizationStatus,
        to newStatus: CLAuthorizationStatus
    ) {
        LocationPermissionHandling.handleAuthorizationChange(
            workout: workout,
            oldStatus: oldStatus,
            newStatus: newStatus,
            pendingStartWorkout: &pendingStartWorkout,
            alert: &alert
        )
    }

    private func alertContent(for kind: LocationPermissionAlert) -> Alert {
        switch kind {
        case .primer:
            return Alert(
                title: Text(PermissionPrimerCopy.locationTitle),
                message: Text(PermissionPrimerCopy.locationMessage),
                primaryButton: .default(Text(PermissionPrimerCopy.allowButtonTitle)) {
                    LocationPermissionHandling.confirmLocationPrimer(workout: workout)
                },
                secondaryButton: .cancel(Text("취소")) {
                    pendingStartWorkout = false
                }
            )
        case .denied:
#if os(iOS)
            return Alert(
                title: Text(PermissionPrimerCopy.locationDeniedTitle),
                message: Text(PermissionPrimerCopy.locationDeniedMessage),
                primaryButton: .default(Text(PermissionPrimerCopy.openSettingsButtonTitle)) {
                    AppSettingsOpener.open()
                    pendingStartWorkout = false
                },
                secondaryButton: .cancel(Text("취소")) {
                    pendingStartWorkout = false
                }
            )
#else
            return Alert(
                title: Text(PermissionPrimerCopy.locationDeniedTitle),
                message: Text(PermissionPrimerCopy.locationDeniedWatchMessage),
                dismissButton: .default(Text("확인")) {
                    pendingStartWorkout = false
                }
            )
#endif
#if os(iOS)
        case .alwaysRecommended:
            return Alert(
                title: Text(PermissionPrimerCopy.locationAlwaysTitle),
                message: Text(PermissionPrimerCopy.locationAlwaysMessage),
                primaryButton: .default(Text("항상 허용")) {
                    workout.requestAlwaysLocationAuthorization()
                },
                secondaryButton: .cancel(Text("앱 사용 중만")) {}
            )
#endif
        }
    }
}

extension View {
    func locationPermissionAlerts(
        workout: WorkoutManager,
        alert: Binding<LocationPermissionAlert?>,
        pendingStartWorkout: Binding<Bool>
    ) -> some View {
        modifier(
            LocationPermissionAlertModifier(
                workout: workout,
                alert: alert,
                pendingStartWorkout: pendingStartWorkout
            )
        )
    }
}
