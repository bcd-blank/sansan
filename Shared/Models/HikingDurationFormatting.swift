//
//  HikingDurationFormatting.swift
//  Shared
//

import Foundation

enum HikingDurationFormatting {
    enum Style {
        /// `45:30` 또는 `1:05:30`
        case standard
        /// `45:30` 또는 `3h 25m` (통계 카드·좁은 영역)
        case compact
    }

    static func displayString(elapsedSeconds: TimeInterval, style: Style) -> String {
        let total = max(0, Int(elapsedSeconds.rounded()))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60

        switch style {
        case .standard:
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            }
            return String(format: "%02d:%02d", minutes, seconds)

        case .compact:
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            }
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
