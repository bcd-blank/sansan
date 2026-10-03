//
//  ElevationChartYAxisSpec.swift
//  sansan
//
//  고도 차트 Y축 — 데이터 범위에 맞춘 1-2-5 눈금. Swift Charts 기본축이
//  1000m를 넘기면 0…10000으로 벌어지는 것을 막습니다.
//

import Foundation

/// 고도 프로필 차트 Y축 범위와 눈금.
struct ElevationChartYAxisSpec: Equatable {
    let domain: ClosedRange<Double>
    let ticks: [Double]

    /// `minAltitude`…`maxAltitude`를 보기 좋게 감싸는 축. 항상 데이터보다 약간 넓습니다.
    static func fitting(
        minAltitude: Double,
        maxAltitude: Double,
        targetTickCount: Int = 5
    ) -> ElevationChartYAxisSpec {
        let lowerRaw = min(minAltitude, maxAltitude)
        let upperRaw = max(minAltitude, maxAltitude)
        let span = max(upperRaw - lowerRaw, 40)
        let padding = max(span * 0.12, 10)
        let paddedLower = lowerRaw - padding
        let paddedUpper = upperRaw + padding

        let step = niceStep((paddedUpper - paddedLower) / Double(max(targetTickCount - 1, 1)))
        let niceLower = (paddedLower / step).rounded(.down) * step
        let niceUpper = max((paddedUpper / step).rounded(.up) * step, niceLower + step)

        var ticks: [Double] = []
        var value = niceLower
        var count = 0
        while value <= niceUpper + step * 0.001, count < 12 {
            ticks.append((value * 10).rounded() / 10)
            value += step
            count += 1
        }
        if ticks.isEmpty {
            ticks = [niceLower, niceUpper]
        }
        return ElevationChartYAxisSpec(domain: niceLower...niceUpper, ticks: ticks)
    }

    /// 1-2-5×10^n 간격. `ceil(log10(max))`로 자릿수를 올리면 1001 → 10000이 되므로
    /// 반드시 `floor(log10(raw))`로 자릿수를 잡습니다.
    static func niceStep(_ raw: Double) -> Double {
        let positive = max(raw, 1)
        let exponent = floor(log10(positive))
        let magnitude = pow(10, exponent)
        let fraction = positive / magnitude
        let niceFraction: Double
        if fraction <= 1 {
            niceFraction = 1
        } else if fraction <= 2 {
            niceFraction = 2
        } else if fraction <= 5 {
            niceFraction = 5
        } else {
            niceFraction = 10
        }
        return niceFraction * magnitude
    }
}
