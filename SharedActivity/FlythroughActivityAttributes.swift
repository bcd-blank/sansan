//
//  FlythroughActivityAttributes.swift
//  sansan
//
//  3D 경로 영상 제작 진행 상황을 다이나믹 아일랜드·잠금화면에 표시하는 Live Activity 모델.
//  앱 타깃과 SansanWidgets 익스텐션이 함께 컴파일합니다(구조가 어긋나면 Activity 디코딩 실패).
//

#if canImport(ActivityKit)

import ActivityKit
import Foundation

nonisolated struct FlythroughActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        /// 전체 진행률 0…1.
        var progress: Double
        /// 현재 단계 이름 (예: "경로 따라가기").
        var stageTitle: String
        /// 앱이 백그라운드로 전환되어 렌더링이 잠시 멈춘 상태인지.
        var isPaused: Bool
    }

    /// 기록 제목 (산 이름 또는 기본 제목).
    var recordTitle: String
}

#endif
