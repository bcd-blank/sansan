//
//  HikingRouteWeatherSnapshot.swift
//  Shared
//

import Foundation

/// 산행 중 같은 날씨가 이어진 한 구간.
nonisolated struct HikingWeatherSegment: Codable, Equatable, Hashable, Sendable {
    var wmoCode: Int
    var startedAt: Date
    var endedAt: Date
}

    /// 산행 중 기온·날씨가 바뀐 시점.
nonisolated struct HikingWeatherHourPoint: Codable, Equatable, Hashable, Sendable, Identifiable {
    var date: Date
    var wmoCode: Int
    var temperatureCelsius: Double

    var id: Date { date }

    var formattedTemperature: String {
        "\(Int(temperatureCelsius.rounded()))°"
    }

    func hasSameDisplayedWeather(as other: HikingWeatherHourPoint) -> Bool {
        formattedTemperature == other.formattedTemperature
            && HikingRouteWeatherSnapshot.conditionLabel(for: wmoCode)
                == HikingRouteWeatherSnapshot.conditionLabel(for: other.wmoCode)
    }
}

/// 산행 구간의 대표 날씨와 기온 요약 (Open-Meteo WMO 코드).
nonisolated struct HikingRouteWeatherSnapshot: Codable, Equatable, Hashable, Sendable {
    var wmoCode: Int
    /// 산행 시간대 평균 기온(°C).
    var temperatureCelsius: Double
    /// 산행 시간대 최저 기온(°C).
    var minimumTemperatureCelsius: Double
    /// 산행 시간대 최고 기온(°C).
    var maximumTemperatureCelsius: Double
    var referenceDate: Date
    /// 시작~종료를 시간순으로 이은 날씨 구간. 구 기록은 비어 있을 수 있습니다.
    var segments: [HikingWeatherSegment]
    /// 산행 중 기온·날씨가 바뀐 시점만. 같은 상태가 이어지면 한 칸입니다.
    var hours: [HikingWeatherHourPoint]
    /// 최저·최고가 파일에 따로 저장돼 있는지. 구 기록은 평균만 있어 다시 받습니다.
    var hasTemperatureExtremes: Bool

    init(
        wmoCode: Int,
        temperatureCelsius: Double,
        referenceDate: Date,
        segments: [HikingWeatherSegment] = [],
        hours: [HikingWeatherHourPoint] = [],
        minimumTemperatureCelsius: Double? = nil,
        maximumTemperatureCelsius: Double? = nil,
        hasTemperatureExtremes: Bool? = nil
    ) {
        self.wmoCode = wmoCode
        self.temperatureCelsius = temperatureCelsius
        let minimum = minimumTemperatureCelsius ?? temperatureCelsius
        let maximum = maximumTemperatureCelsius ?? temperatureCelsius
        self.minimumTemperatureCelsius = min(minimum, maximum)
        self.maximumTemperatureCelsius = max(minimum, maximum)
        self.referenceDate = referenceDate
        self.segments = segments
        self.hours = Self.changePoints(from: hours)
        self.hasTemperatureExtremes = hasTemperatureExtremes
            ?? (minimumTemperatureCelsius != nil && maximumTemperatureCelsius != nil)
    }

    enum CodingKeys: String, CodingKey {
        case wmoCode, temperatureCelsius, referenceDate, segments, hours
        case minimumTemperatureCelsius, maximumTemperatureCelsius
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wmoCode = try container.decode(Int.self, forKey: .wmoCode)
        temperatureCelsius = try container.decode(Double.self, forKey: .temperatureCelsius)
        referenceDate = try container.decode(Date.self, forKey: .referenceDate)
        segments = try container.decodeIfPresent([HikingWeatherSegment].self, forKey: .segments) ?? []
        hours = Self.changePoints(
            from: try container.decodeIfPresent([HikingWeatherHourPoint].self, forKey: .hours) ?? []
        )
        let decodedMinimum = try container.decodeIfPresent(Double.self, forKey: .minimumTemperatureCelsius)
        let decodedMaximum = try container.decodeIfPresent(Double.self, forKey: .maximumTemperatureCelsius)
        hasTemperatureExtremes = decodedMinimum != nil && decodedMaximum != nil
        let minimum = decodedMinimum ?? temperatureCelsius
        let maximum = decodedMaximum ?? temperatureCelsius
        minimumTemperatureCelsius = min(minimum, maximum)
        maximumTemperatureCelsius = max(minimum, maximum)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wmoCode, forKey: .wmoCode)
        try container.encode(temperatureCelsius, forKey: .temperatureCelsius)
        try container.encode(minimumTemperatureCelsius, forKey: .minimumTemperatureCelsius)
        try container.encode(maximumTemperatureCelsius, forKey: .maximumTemperatureCelsius)
        try container.encode(referenceDate, forKey: .referenceDate)
        if !segments.isEmpty {
            try container.encode(segments, forKey: .segments)
        }
        if !hours.isEmpty {
            try container.encode(hours, forKey: .hours)
        }
    }

    var formattedTemperature: String {
        "\(Int(temperatureCelsius.rounded()))°"
    }

    var formattedAverageTemperature: String {
        "평균 \(formattedTemperature)"
    }

    var formattedTemperatureRange: String {
        "최저 \(Int(minimumTemperatureCelsius.rounded()))°  최고 \(Int(maximumTemperatureCelsius.rounded()))°"
    }

    var showsTemperatureRange: Bool {
        Int(minimumTemperatureCelsius.rounded()) != Int(maximumTemperatureCelsius.rounded())
    }

    var needsWeatherRefresh: Bool {
        !hasTemperatureExtremes || hours.isEmpty
    }

    /// 타임라인에 그릴 변화 시점. 구 기록은 대표값 한 칸으로 대체합니다.
    var timelineHours: [HikingWeatherHourPoint] {
        let source: [HikingWeatherHourPoint]
        if hours.isEmpty {
            source = [
                HikingWeatherHourPoint(
                    date: referenceDate,
                    wmoCode: wmoCode,
                    temperatureCelsius: temperatureCelsius
                )
            ]
        } else {
            source = hours.sorted { $0.date < $1.date }
        }
        return Self.changePoints(from: source)
    }

    /// 표시 기온이나 날씨 라벨이 바뀐 시점만 남깁니다.
    static func changePoints(from points: [HikingWeatherHourPoint]) -> [HikingWeatherHourPoint] {
        var kept: [HikingWeatherHourPoint] = []
        for point in points.sorted(by: { $0.date < $1.date }) {
            if let last = kept.last, last.hasSameDisplayedWeather(as: point) {
                continue
            }
            kept.append(point)
        }
        return kept
    }

    var symbolName: String {
        Self.symbolName(for: wmoCode)
    }

    var conditionLabel: String {
        Self.conditionLabel(for: wmoCode)
    }

    /// 산행 중 날씨 요약. 같은 날씨가 오락가락하면 한 번만 적습니다.
    var changeSummary: String {
        let labels = uniqueConditionLabels
        if labels.isEmpty {
            return conditionLabel
        }
        return labels.joined(separator: " → ")
    }

    var hasConditionChanges: Bool {
        uniqueConditionLabels.count > 1
    }

    var conditionLabelsInOrder: [String] {
        let labels = segments.map { Self.conditionLabel(for: $0.wmoCode) }
        return labels.isEmpty ? [conditionLabel] : labels
    }

    /// 시간순으로 처음 등장한 날씨만. 시간마다 이어 붙이지 않습니다.
    var uniqueConditionLabels: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for label in conditionLabelsInOrder where seen.insert(label).inserted {
            ordered.append(label)
        }
        if ordered.count <= 3 {
            return ordered
        }
        let strongest = Self.conditionLabel(for: wmoCode)
        var compact = [ordered[0]]
        if !compact.contains(strongest) {
            compact.append(strongest)
        }
        if let last = ordered.last, !compact.contains(last) {
            compact.append(last)
        }
        return compact
    }

    static func symbolName(for code: Int) -> String {
        switch code {
        case 0:
            return "sun.max.fill"
        case 1, 2, 3:
            return "cloud.sun.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82:
            return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86:
            return "cloud.snow.fill"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }

    static func conditionLabel(for code: Int) -> String {
        switch code {
        case 0:
            return "맑음"
        case 1, 2, 3:
            return "구름 조금"
        case 45, 48:
            return "안개"
        case 51, 53, 55, 56, 57:
            return "이슬비"
        case 61, 63, 65, 66, 67:
            return "비"
        case 71, 73, 75, 77:
            return "눈"
        case 80, 81, 82:
            return "소나기"
        case 85, 86:
            return "눈보라"
        case 95, 96, 99:
            return "뇌우"
        default:
            return "흐림"
        }
    }
}
