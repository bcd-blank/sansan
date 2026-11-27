import CoreGraphics
import CoreLocation
import Foundation
import MapKit

/// Render-only path smoothing. Stored GPS / distance must never use this array.
/// Tokens: `docs/design-tokens/route-corner-smooth.json`.
///
/// Spec (v4 — centripetal Catmull-Rom through kept points):
/// 1. Input = one stretch of saved original points (save order). Skip only
///    duplicates &lt;0.5 m from last kept; no other drop/move.
/// 2. Centripetal Catmull-Rom α=0.5 through ALL kept points. Per segment,
///    subdivide by screen length 1 sample / 2 px (min 2, max 16). Duplicate ends
///    for controls.
/// 3. Meter plane (ENU / mercator). |Δzoom|≥0.5 → callers recompute (subdiv counts).
/// 4. Token `v4-catmull-through-points`. Casing/fill 9/5/0.9 round unchanged.
enum RouteCornerSmoothing {
    static let alongFractionOfMinSide: CGFloat = 0.01
    /// Canvas/pt fallback when no map size is known.
    static let maxFilletAlongPt: CGFloat = 4
    static let catmullAlpha: CGFloat = 0.5
    static let subdivPxPerSample: CGFloat = 2
    static let subdivMin: Int = 2
    static let subdivMax: Int = 16
    /// Drop consecutive duplicates closer than this (meters).
    static let duplicateMinSeparationMeters: CLLocationDistance = 0.5
    static let zoomRecalcDelta: Double = 0.5

    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-SANSAN_ROUTE_CORNER_SHARP") { return false }
        if ProcessInfo.processInfo.environment["SANSAN_ROUTE_CORNER_SHARP"] == "1" { return false }
        return true
    }

    /// L in screen pt = 1% of the shorter map side (kept for dump / callers).
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

    /// t_m = L × metersPerPoint (dump / legacy callers; v4 subdiv uses mpp directly).
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

    /// If Part A finds save order ≠ timestamp order, sort render input by timestamp only.
    /// No GPS jitter filter — report numbers; JW decides filter.
    static func sortByTimestampIfNeeded<T>(
        _ items: [T],
        timestamp: (T) -> Date?,
        saveOrderMatchesTimestamp: Bool
    ) -> [T] {
        guard !saveOrderMatchesTimestamp, items.count >= 2 else { return items }
        var indexed = Array(items.enumerated())
        indexed.sort { a, b in
            let ta = timestamp(a.element)
            let tb = timestamp(b.element)
            switch (ta, tb) {
            case let (ta?, tb?):
                if ta != tb { return ta < tb }
                return a.offset < b.offset
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return a.offset < b.offset
            }
        }
        return indexed.map(\.element)
    }

    /// Pt-space path (canvas / snapshot).
    /// - `metersPerUnit`: meters represented by one CGPoint unit (1 for canvas pt).
    /// - `metersPerScreenPoint`: meters per screen point/px (1 for canvas pt → subdiv in pt).
    static func smoothPoints(
        _ points: [CGPoint],
        metersPerUnit: CGFloat,
        metersPerScreenPoint: CGFloat
    ) -> [CGPoint] {
        guard isEnabled, points.count >= 2 else { return points }
        guard metersPerUnit > 1e-18, metersPerScreenPoint > 1e-18 else { return points }
        let kept = dropNearDuplicates(points, metersPerUnit: metersPerUnit)
        guard kept.count >= 2 else { return points }
        return centripetalCatmullRomThrough(
            kept,
            alpha: catmullAlpha,
            metersPerUnit: metersPerUnit,
            metersPerScreenPoint: metersPerScreenPoint
        )
    }

    /// Canvas convenience: treat pt as unit+screen scale (subdiv by pt length / 2).
    static func smoothPoints(
        _ points: [CGPoint],
        maxAlong: CGFloat
    ) -> [CGPoint] {
        // maxAlong retained for call-site compatibility; v4 ignores t_m resample.
        _ = maxAlong
        return smoothPoints(points, metersPerUnit: 1, metersPerScreenPoint: 1)
    }

    /// Map path — pass camera `metersPerPoint` and screen `alongPt` (= L).
    /// Operates in mercator map-point plane (meters via mid-lat scale).
    static func smoothCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        metersPerPoint: CLLocationDistance,
        alongPt: CGFloat
    ) -> [CLLocationCoordinate2D] {
        guard isEnabled, coordinates.count >= 2 else { return coordinates }
        _ = alongPt // dump / legacy; subdiv uses metersPerPoint directly
        guard metersPerPoint > 1e-12 else { return coordinates }
        let mapPoints = coordinates.map { MKMapPoint($0) }
        let midLat = coordinates[coordinates.count / 2].latitude
        let metersPerMapPoint = MKMetersPerMapPointAtLatitude(midLat)
        guard metersPerMapPoint > 1e-12 else { return coordinates }
        let raw = mapPoints.map { CGPoint(x: $0.x, y: $0.y) }
        let smoothed = smoothPoints(
            raw,
            metersPerUnit: CGFloat(metersPerMapPoint),
            metersPerScreenPoint: CGFloat(metersPerPoint)
        )
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

    // MARK: - v4 pipeline

    /// Keep first; skip points &lt;0.5 m from last kept; always keep last.
    private static func dropNearDuplicates(
        _ points: [CGPoint],
        metersPerUnit: CGFloat
    ) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        let minSepUnits = CGFloat(duplicateMinSeparationMeters) / metersPerUnit
        var kept: [CGPoint] = [points[0]]
        for i in 1..<(points.count - 1) {
            let p = points[i]
            let prev = kept[kept.count - 1]
            if hypot(p.x - prev.x, p.y - prev.y) >= minSepUnits {
                kept.append(p)
            }
        }
        let last = points[points.count - 1]
        if let prev = kept.last {
            if hypot(last.x - prev.x, last.y - prev.y) >= 1e-12 {
                kept.append(last)
            } else {
                kept[kept.count - 1] = last
            }
        } else {
            kept.append(last)
        }
        return kept
    }

    private static func subdivisionCount(
        from: CGPoint,
        to: CGPoint,
        metersPerUnit: CGFloat,
        metersPerScreenPoint: CGFloat
    ) -> Int {
        let units = hypot(to.x - from.x, to.y - from.y)
        let meters = units * metersPerUnit
        let screenPx = meters / metersPerScreenPoint
        let raw = Int((screenPx / subdivPxPerSample).rounded())
        return max(subdivMin, min(subdivMax, max(raw, subdivMin)))
    }

    /// Centripetal Catmull-Rom through all points. Duplicate ends for controls.
    /// Per-segment subdivision from screen length (1 / 2 px, clamp 2…16).
    private static func centripetalCatmullRomThrough(
        _ points: [CGPoint],
        alpha: CGFloat,
        metersPerUnit: CGFloat,
        metersPerScreenPoint: CGFloat
    ) -> [CGPoint] {
        let n = points.count
        guard n >= 2 else { return points }
        if n == 2 {
            let subdiv = subdivisionCount(
                from: points[0],
                to: points[1],
                metersPerUnit: metersPerUnit,
                metersPerScreenPoint: metersPerScreenPoint
            )
            var out: [CGPoint] = [points[0]]
            for s in 1..<subdiv {
                let u = CGFloat(s) / CGFloat(subdiv)
                out.append(CGPoint(
                    x: points[0].x + (points[1].x - points[0].x) * u,
                    y: points[0].y + (points[1].y - points[0].y) * u
                ))
            }
            out.append(points[1])
            return out
        }

        // Duplicate ends for control points.
        var ctrl = [CGPoint]()
        ctrl.reserveCapacity(n + 2)
        ctrl.append(points[0])
        ctrl.append(contentsOf: points)
        ctrl.append(points[n - 1])

        var out: [CGPoint] = []
        out.reserveCapacity(n * subdivMax)
        out.append(points[0])

        for i in 1..<(ctrl.count - 2) {
            let p0 = ctrl[i - 1]
            let p1 = ctrl[i]
            let p2 = ctrl[i + 1]
            let p3 = ctrl[i + 2]
            let subdiv = subdivisionCount(
                from: p1,
                to: p2,
                metersPerUnit: metersPerUnit,
                metersPerScreenPoint: metersPerScreenPoint
            )
            let t0: CGFloat = 0
            let t1 = t0 + pow(max(hypot(p1.x - p0.x, p1.y - p0.y), 1e-12), alpha)
            let t2 = t1 + pow(max(hypot(p2.x - p1.x, p2.y - p1.y), 1e-12), alpha)
            let t3 = t2 + pow(max(hypot(p3.x - p2.x, p3.y - p2.y), 1e-12), alpha)
            // Sample interior of [p1,p2]; land exactly on kept p2 at segment end.
            for s in 1...subdiv {
                if s == subdiv {
                    out.append(ctrl[i + 1])
                } else {
                    let u = CGFloat(s) / CGFloat(subdiv)
                    let t = t1 + (t2 - t1) * u
                    out.append(catmullPoint(
                        p0: p0, p1: p1, p2: p2, p3: p3,
                        t0: t0, t1: t1, t2: t2, t3: t3, t: t
                    ))
                }
            }
        }
        out[0] = points[0]
        if out.isEmpty {
            out.append(points[n - 1])
        } else {
            out[out.count - 1] = points[n - 1]
        }
        return out
    }

    private static func catmullPoint(
        p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint,
        t0: CGFloat, t1: CGFloat, t2: CGFloat, t3: CGFloat,
        t: CGFloat
    ) -> CGPoint {
        func lerp(_ a: CGPoint, _ b: CGPoint, _ ta: CGFloat, _ tb: CGFloat, _ t: CGFloat) -> CGPoint {
            let den = tb - ta
            if abs(den) < 1e-12 { return a }
            let u = (t - ta) / den
            return CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
        }
        let a1 = lerp(p0, p1, t0, t1, t)
        let a2 = lerp(p1, p2, t1, t2, t)
        let a3 = lerp(p2, p3, t2, t3, t)
        let b1 = lerp(a1, a2, t0, t2, t)
        let b2 = lerp(a2, a3, t1, t3, t)
        return lerp(b1, b2, t1, t2, t)
    }
}
