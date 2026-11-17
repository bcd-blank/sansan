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
        let locale = Locale(identifier: "ko_KR")

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.dateFormat = "yyyy M d"
        let dateText = dateFormatter.string(from: self)

        // Android DateText.time = "a h:mm" → share concatenates as 「오후 7:37」.
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.dateFormat = "h:mm"
        let timeText = timeFormatter.string(from: self)

        let periodFormatter = DateFormatter()
        periodFormatter.locale = locale
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
