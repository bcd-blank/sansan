//
//  ScheduleDateParts.swift
//  Shared
//

import Foundation

/// 시작·종료 카드용 날짜·시간 분리 표시.
struct ScheduleDateParts: Sendable, Hashable {
    let dateText: String
    let timeText: String
    let periodText: String?
}

extension Date {
    var scheduleDisplayParts: ScheduleDateParts {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ko_KR")
        dateFormatter.dateFormat = "yyyy M d"
        let dateText = dateFormatter.string(from: self)

        let timeText = formatted(
            .dateTime
                .hour(.defaultDigits(amPM: .omitted))
                .minute()
        )

        let periodFormatter = DateFormatter()
        periodFormatter.locale = Locale.current
        periodFormatter.dateFormat = "a"
        let period = periodFormatter.string(from: self).trimmingCharacters(in: .whitespaces)
        let periodText = period.isEmpty ? nil : period

        return ScheduleDateParts(
            dateText: dateText,
            timeText: timeText,
            periodText: periodText
        )
    }
}

extension SavedHikingSession {
    var startedScheduleParts: ScheduleDateParts? {
        startedAt?.scheduleDisplayParts
    }

    var endedScheduleParts: ScheduleDateParts {
        endedAt.scheduleDisplayParts
    }
}
