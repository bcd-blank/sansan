//
//  HikingRouteWeatherService.swift
//  Shared
//
//  Open-Meteo — 산행 시작~종료 구간의 시간별 날씨를 보고 대표 상태를 고릅니다.
//

import CoreLocation
import Foundation

enum HikingRouteWeatherService {
    private static let timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current

    /// 이 일수 이내는 관측을 반영하는 forecast API(past_days)를 사용한다.
    /// Open-Meteo archive(ERA5)는 최근 수일이 모델 추정값이라 실제와 어긋날 수 있다.
    private static let recentDayThreshold = 60

    /// 강수량이 이 값 이상이면 weather_code가 맑음이어도 비/소나기로 보정한다.
    static let precipitationOverrideMillimeters = 0.2

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()

    static func fetch(
        coordinate: CLLocationCoordinate2D,
        from start: Date,
        to end: Date
    ) async -> HikingRouteWeatherSnapshot? {
        let rangeStart = min(start, end)
        let rangeEnd = max(start, end)
        let daysAgo = daysBetween(rangeStart, and: Date())

        if daysAgo <= recentDayThreshold {
            if let snapshot = await fetchFromForecast(
                coordinate: coordinate,
                from: rangeStart,
                to: rangeEnd,
                daysAgo: daysAgo
            ) {
                return snapshot
            }
        }
        return await fetchFromArchive(coordinate: coordinate, from: rangeStart, to: rangeEnd)
    }

    /// 관측을 반영하는 forecast API. 오늘·최근 기록의 정확도가 archive보다 높다.
    private static func fetchFromForecast(
        coordinate: CLLocationCoordinate2D,
        from start: Date,
        to end: Date,
        daysAgo: Int
    ) async -> HikingRouteWeatherSnapshot? {
        let pastDays = min(92, max(1, daysAgo + 1))
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.5f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.5f", coordinate.longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation,showers"),
            URLQueryItem(name: "past_days", value: String(pastDays)),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "Asia/Seoul"),
        ]
        return await request(components, from: start, to: end)
    }

    /// 오래된 기록용 ERA5 재분석 archive API.
    private static func fetchFromArchive(
        coordinate: CLLocationCoordinate2D,
        from start: Date,
        to end: Date
    ) async -> HikingRouteWeatherSnapshot? {
        var components = URLComponents(string: "https://archive-api.open-meteo.com/v1/archive")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.5f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.5f", coordinate.longitude)),
            URLQueryItem(name: "start_date", value: dayFormatter.string(from: start)),
            URLQueryItem(name: "end_date", value: dayFormatter.string(from: end)),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation,showers"),
            URLQueryItem(name: "timezone", value: "Asia/Seoul"),
        ]
        return await request(components, from: start, to: end)
    }

    private static func request(
        _ components: URLComponents?,
        from start: Date,
        to end: Date
    ) async -> HikingRouteWeatherSnapshot? {
        guard let url = components?.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return parseResponse(data, from: start, to: end)
        } catch {
            return nil
        }
    }

    private static func daysBetween(_ start: Date, and end: Date) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        var calendarWithZone = calendar
        calendarWithZone.timeZone = timeZone
        let startDay = calendarWithZone.startOfDay(for: start)
        let endDay = calendarWithZone.startOfDay(for: end)
        let days = calendarWithZone.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return max(0, days)
    }

    static func parseResponse(_ data: Data, from start: Date, to end: Date) -> HikingRouteWeatherSnapshot? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let hourly = json["hourly"] as? [String: Any],
            let times = hourly["time"] as? [String],
            let temperatures = hourly["temperature_2m"] as? [Double],
            let codes = hourly["weather_code"] as? [Int],
            !times.isEmpty,
            times.count == temperatures.count,
            times.count == codes.count
        else {
            return nil
        }

        let precipitations = hourly["precipitation"] as? [Double]
        let showers = hourly["showers"] as? [Double]
        var samples: [HourlyWeatherSample] = []
        samples.reserveCapacity(times.count)

        for index in times.indices {
            guard let hourDate = hourFormatter.date(from: times[index]) else { continue }
            samples.append(
                HourlyWeatherSample(
                    date: hourDate,
                    temperatureCelsius: temperatures[index],
                    weatherCode: codes[index],
                    precipitationMillimeters: precipitations?[safe: index] ?? 0,
                    showersMillimeters: showers?[safe: index] ?? 0
                )
            )
        }

        return snapshot(from: samples, start: start, end: end)
    }

    /// 산행 구간에 겹치는 시간 중 가장 강한 날씨를 고르고, 강수량이 있으면 맑음 코드를 보정합니다.
    static func snapshot(
        from samples: [HourlyWeatherSample],
        start: Date,
        end: Date
    ) -> HikingRouteWeatherSnapshot? {
        guard !samples.isEmpty else { return nil }

        let rangeStart = min(start, end)
        let rangeEnd = max(start, end)
        let overlapping = samples.filter { sampleOverlapsHike($0.date, start: rangeStart, end: rangeEnd) }
        let window = overlapping.isEmpty ? closestSamples(in: samples, to: rangeStart) : overlapping

        let temperatures = window.map(\.temperatureCelsius)
        let temperature = temperatures.reduce(0, +) / Double(temperatures.count)
        let minimum = temperatures.min() ?? temperature
        let maximum = temperatures.max() ?? temperature
        let segments = weatherSegments(from: window, start: rangeStart, end: rangeEnd)
        let strongestCode = segments
            .map(\.wmoCode)
            .max(by: { severity(of: $0) < severity(of: $1) })
            ?? resolvedWeatherCode(
                strongestCode: window.max(by: { severity(of: $0.weatherCode) < severity(of: $1.weatherCode) })?.weatherCode ?? 0,
                precipitation: window.map(\.precipitationMillimeters).max() ?? 0,
                showers: window.map(\.showersMillimeters).max() ?? 0
            )

        let hours = HikingRouteWeatherSnapshot.changePoints(
            from: window.sorted { $0.date < $1.date }.map { sample in
                HikingWeatherHourPoint(
                    date: sample.date,
                    wmoCode: resolvedCode(for: sample),
                    temperatureCelsius: sample.temperatureCelsius
                )
            }
        )

        return HikingRouteWeatherSnapshot(
            wmoCode: strongestCode,
            temperatureCelsius: temperature,
            referenceDate: rangeStart,
            segments: segments,
            hours: hours,
            minimumTemperatureCelsius: minimum,
            maximumTemperatureCelsius: maximum
        )
    }

    /// 연속된 같은 날씨 라벨을 한 구간으로 묶습니다.
    static func weatherSegments(
        from samples: [HourlyWeatherSample],
        start: Date,
        end: Date
    ) -> [HikingWeatherSegment] {
        let sorted = samples.sorted { $0.date < $1.date }
        guard let first = sorted.first else { return [] }

        var segments: [HikingWeatherSegment] = []
        var currentCode = resolvedCode(for: first)
        var currentStart = max(first.date, start)

        for sample in sorted.dropFirst() {
            let code = resolvedCode(for: sample)
            if HikingRouteWeatherSnapshot.conditionLabel(for: code)
                != HikingRouteWeatherSnapshot.conditionLabel(for: currentCode) {
                let segmentEnd = min(max(sample.date, currentStart), end)
                if segmentEnd > currentStart {
                    segments.append(
                        HikingWeatherSegment(wmoCode: currentCode, startedAt: currentStart, endedAt: segmentEnd)
                    )
                }
                currentCode = code
                currentStart = max(sample.date, start)
            }
        }

        let lastEnd = min(end, max(sorted.last?.date.addingTimeInterval(3600) ?? end, currentStart))
        if lastEnd > currentStart {
            segments.append(
                HikingWeatherSegment(wmoCode: currentCode, startedAt: currentStart, endedAt: lastEnd)
            )
        }
        return segments
    }

    static func resolvedCode(for sample: HourlyWeatherSample) -> Int {
        resolvedWeatherCode(
            strongestCode: sample.weatherCode,
            precipitation: sample.precipitationMillimeters,
            showers: sample.showersMillimeters
        )
    }

    static func resolvedWeatherCode(
        strongestCode: Int,
        precipitation: Double,
        showers: Double
    ) -> Int {
        if severity(of: strongestCode) >= 40 {
            return strongestCode
        }
        if showers >= precipitationOverrideMillimeters {
            return 80
        }
        if precipitation >= precipitationOverrideMillimeters {
            return 61
        }
        return strongestCode
    }

    /// WMO 코드가 강할수록 큰 값. 산행 중 잠깐의 소나기를 맑음보다 우선한다.
    static func severity(of code: Int) -> Int {
        switch code {
        case 95, 96, 99: return 90
        case 85, 86: return 80
        case 71, 73, 75, 77: return 70
        case 80, 81, 82: return 60
        case 61, 63, 65, 66, 67: return 50
        case 51, 53, 55, 56, 57: return 40
        case 45, 48: return 20
        case 3: return 15
        case 1, 2: return 10
        case 0: return 0
        default: return 12
        }
    }

    private static func sampleOverlapsHike(_ hour: Date, start: Date, end: Date) -> Bool {
        let hourEnd = hour.addingTimeInterval(3600)
        return hour < end && hourEnd > start
    }

    private static func closestSamples(in samples: [HourlyWeatherSample], to date: Date) -> [HourlyWeatherSample] {
        guard let closest = samples.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) else {
            return samples
        }
        return [closest]
    }
}

struct HourlyWeatherSample: Equatable, Sendable {
    var date: Date
    var temperatureCelsius: Double
    var weatherCode: Int
    var precipitationMillimeters: Double
    var showersMillimeters: Double
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
