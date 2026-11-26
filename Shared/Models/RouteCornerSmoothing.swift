import CoreGraphics
import CoreLocation
import Foundation
import MapKit

/// Render-only path smoothing. Stored GPS / distance must never use this array.
/// Tokens: `docs/design-tokens/route-corner-smooth.json`.
///
/// Spec (JW replace — no per-vert Bezier):
/// 1. Input = screen draw verts. t_m = 0.01×min(mapW,mapH)×mpp (fit ≈ 15m).
/// 2. Uniform resample by cumulative distance, step h = t_m/4 (linear).
/// 3. Moving average over ±t_m window (W = 2·t_m/h+1 = 9, uniform). Ends shrink
///    symmetrically; start/end fixed.
/// 4. Callers stretch-split the smoothed path; casing/fill 9/5/0.9 round.
enum RouteCornerSmoothing {
    static let alongFractionOfMinSide: CGFloat = 0.01
    /// Canvas/pt fallback when no map size is known.
    static let maxFilletAlongPt: CGFloat = 4

    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-SANSAN_ROUTE_CORNER_SHARP") { return false }
        if ProcessInfo.processInfo.environment["SANSAN_ROUTE_CORNER_SHARP"] == "1" { return false }
        return true
    }

    /// L in screen pt = 1% of the shorter map side.
    static func alongPt(mapWidth: CGFloat, mapHeight: CGFloat) -> CGFloat {
        let side = min(mapWidth, mapHeight)
        guard side > 1 else { return maxFilletAlongPt }
        return alongFractionOfMinSide * side
    }

    /// Screen meters per point at the given camera.
    static func metersPerPoint(
        latitude: CLLocationDegrees,
        visibleMapRect: MKMapRect,
        boundsWidth: CGFloat
    ) -> CLLocationDistance {
        guard boundsWidth > 1, visibleMapRect.size.width > 0 else { return 0 }
        return MKMetersPerMapPointAtLatitude(latitude)
            * (visibleMapRect.width / Double(boundsWidth))
    }

    /// t_m = L × metersPerPoint.
    static func maxAlongMeters(
        metersPerPoint: CLLocationDistance,
        alongPt: CGFloat
    ) -> CLLocationDistance {
        guard metersPerPoint > 0, alongPt > 0 else { return 0 }
        return CLLocationDistance(alongPt) * metersPerPoint
    }

    static func zoomLevel(longitudeDelta: CLLocationDegrees) -> Double {
        log2(360.0 / max(longitudeDelta, 1e-12))
    }

    /// Pt-space path (canvas / snapshot). `maxAlong` = t_m in the same unit as `points`.
    static func smoothPoints(
        _ points: [CGPoint],
        maxAlong: CGFloat
    ) -> [CGPoint] {
        guard isEnabled, points.count >= 2, maxAlong > 1e-9 else { return points }
        let h = maxAlong / 4
        guard h > 1e-12 else { return points }
        let resampled = resampleUniform(points, step: h)
        return movingAverage(resampled, halfWindow: 4)
    }

    /// Map path — pass camera `metersPerPoint` and screen `alongPt` (= L).
    static func smoothCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        metersPerPoint: CLLocationDistance,
        alongPt: CGFloat
    ) -> [CLLocationCoordinate2D] {
        guard isEnabled, coordinates.count >= 2 else { return coordinates }
        let tMeters = maxAlongMeters(metersPerPoint: metersPerPoint, alongPt: alongPt)
        guard tMeters > 1e-9 else { return coordinates }
        let mapPoints = coordinates.map { MKMapPoint($0) }
        let midLat = coordinates[coordinates.count / 2].latitude
        let metersPerMapPoint = MKMetersPerMapPointAtLatitude(midLat)
        guard metersPerMapPoint > 1e-12 else { return coordinates }
        let maxAlong = CGFloat(tMeters / metersPerMapPoint)
        let raw = mapPoints.map { CGPoint(x: $0.x, y: $0.y) }
        let smoothed = smoothPoints(raw, maxAlong: maxAlong)
        return smoothed.map {
            MKMapPoint(x: Double($0.x), y: Double($0.y)).coordinate
        }
    }

    /// Convenience from fitting region + map size.
    static func smoothCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        fittingRegion: MKCoordinateRegion,
        mapWidth: CGFloat,
        mapHeight: CGFloat
    ) -> [CLLocationCoordinate2D] {
        let mpp = metersPerPoint(
            latitude: fittingRegion.center.latitude,
            visibleMapRect: fittingRegion.mapRect,
            boundsWidth: mapWidth
        )
        return smoothCoordinates(
            coordinates,
            metersPerPoint: mpp,
            alongPt: alongPt(mapWidth: mapWidth, mapHeight: mapHeight)
        )
    }

    // MARK: - Resample + moving average

    /// Linear interpolate along cumulative distance at uniform step `h`.
    private static func resampleUniform(_ points: [CGPoint], step h: CGFloat) -> [CGPoint] {
        guard points.count >= 2, h > 1e-12 else { return points }
        var cum: [CGFloat] = [0]
        cum.reserveCapacity(points.count)
        for i in 1..<points.count {
            let d = hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
            cum.append(cum[i - 1] + d)
        }
        let total = cum[cum.count - 1]
        guard total > 1e-9 else { return [points[0], points[points.count - 1]] }

        var out: [CGPoint] = []
        out.reserveCapacity(Int(total / h) + 2)
        out.append(points[0])
        var target = h
        var seg = 0
        while target < total - 1e-9 {
            while seg < cum.count - 2, cum[seg + 1] < target {
                seg += 1
            }
            let d0 = cum[seg]
            let d1 = cum[seg + 1]
            let span = d1 - d0
            let t = span > 1e-12 ? (target - d0) / span : 0
            let a = points[seg]
            let b = points[seg + 1]
            out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            target += h
        }
        let last = points[points.count - 1]
        if let prev = out.last, hypot(prev.x - last.x, prev.y - last.y) > 1e-9 {
            out.append(last)
        } else if out.isEmpty {
            out.append(last)
        } else {
            out[out.count - 1] = last
        }
        return out
    }

    /// Uniform moving average. `halfWindow` = 4 → W = 9 = 2·t_m/h+1.
    /// Near ends the window shrinks symmetrically; index 0 and last stay fixed.
    private static func movingAverage(_ points: [CGPoint], halfWindow r: Int) -> [CGPoint] {
        let n = points.count
        guard n >= 2, r > 0 else { return points }
        var out = Array(repeating: CGPoint.zero, count: n)
        out[0] = points[0]
        out[n - 1] = points[n - 1]
        if n == 2 { return out }
        for i in 1..<(n - 1) {
            let left = min(r, i, n - 1 - i)
            let lo = i - left
            let hi = i + left
            var sx: CGFloat = 0
            var sy: CGFloat = 0
            let count = hi - lo + 1
            for j in lo...hi {
                sx += points[j].x
                sy += points[j].y
            }
            out[i] = CGPoint(x: sx / CGFloat(count), y: sy / CGFloat(count))
        }
        return out
    }
}
