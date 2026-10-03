//
//  WorkoutChromeStateObserver.swift
//  Shared
//
//  탭·기록 버튼은 GPS 틱마다 다시 그리지 않도록, 크롬에 필요한 상태만 전달합니다.
//

#if os(iOS)

import Combine
import CoreLocation
import Foundation

@MainActor
final class WorkoutChromeStateObserver: ObservableObject {
    static let shared = WorkoutChromeStateObserver()

    @Published private(set) var sessionState: HikingSessionState = .idle
    @Published private(set) var startCountdownRemaining: Int?
    @Published private(set) var summarySession: HikingSessionData?
    @Published private(set) var shouldPresentRecordsList = false
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let workout = WorkoutManager.shared
        sessionState = workout.sessionData.state
        startCountdownRemaining = workout.startCountdownRemaining
        summarySession = workout.summarySession
        shouldPresentRecordsList = workout.shouldPresentRecordsList
        authorizationStatus = workout.authorizationStatus

        workout.$sessionData
            .map(\.state)
            .removeDuplicates()
            .sink { [weak self] state in
                self?.sessionState = state
            }
            .store(in: &cancellables)

        workout.$startCountdownRemaining
            .removeDuplicates()
            .sink { [weak self] remaining in
                self?.startCountdownRemaining = remaining
            }
            .store(in: &cancellables)

        workout.$summarySession
            .sink { [weak self] session in
                self?.summarySession = session
            }
            .store(in: &cancellables)

        workout.$shouldPresentRecordsList
            .removeDuplicates()
            .sink { [weak self] shouldShow in
                self?.shouldPresentRecordsList = shouldShow
            }
            .store(in: &cancellables)

        workout.$authorizationStatus
            .removeDuplicates()
            .sink { [weak self] status in
                self?.authorizationStatus = status
            }
            .store(in: &cancellables)
    }
}

#endif
