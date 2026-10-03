//
//  WorkoutDashboardPulseObserver.swift
//  Shared
//
//  메인 지도는 GPS 틱마다 다시 그리지 않습니다. 1초 또는 상태 변경 때만 화면을 갱신합니다.
//

#if os(iOS)

import Combine
import Foundation

@MainActor
final class WorkoutDashboardPulseObserver: ObservableObject {
    static let shared = WorkoutDashboardPulseObserver()

    @Published private(set) var pulse: UInt = 0

    private var lastPointCount = -1
    private var lastElapsedSecond = -1
    private var lastPhotoCount = -1
    private var cancellables = Set<AnyCancellable>()

    private init() {
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.publishIfDisplayChanged()
            }
            .store(in: &cancellables)

        let workout = WorkoutManager.shared
        workout.$sessionData
            .map(\.state)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.pulse += 1
            }
            .store(in: &cancellables)

        workout.$resumeHikingPrompt
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.pulse += 1
            }
            .store(in: &cancellables)

        workout.$authorizationStatus
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.pulse += 1
            }
            .store(in: &cancellables)
    }

    private func publishIfDisplayChanged() {
        let session = WorkoutManager.shared.sessionData
        let elapsedSecond = Int(session.elapsedTime)
        let pointCount = session.points.count
        let photoCount = session.photos.count
        guard pointCount != lastPointCount
            || elapsedSecond != lastElapsedSecond
            || photoCount != lastPhotoCount
            || session.state != .idle else { return }
        lastPointCount = pointCount
        lastElapsedSecond = elapsedSecond
        lastPhotoCount = photoCount
        pulse += 1
    }
}

#endif
