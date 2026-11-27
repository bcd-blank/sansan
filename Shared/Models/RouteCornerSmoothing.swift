import CoreGraphics
import CoreLocation
import Foundation
import MapKit

/// Render-only path smoothing. Stored GPS / distance must never use this array.
/// Tokens: `docs/design-tokens/route-corner-smooth.json`.
///
/// Spec (v5 — dejitter then centripetal Catmull-Rom through kept points):
/// 1. Split by `segmentBreaks` (no line across pause↔resume).
/// 2. Per pause-segment: drop dups &lt;0.5 m; iterative rebound dejitter
///    (Δ&gt;120°, arms≤30 m, acc&gt;min(a,b); default acc 10 m; max 5 passes;
///    first/last of segment fixed); then Catmull-Rom α=0.5 through remaining
///    (subdiv screenLen/2 px, clamp 2…16). No Catmull controls across segments.
/// 3. Token `v5-catmull-through-points-dejitter`. Casing/fill 9/5/0.9 round unchanged.
/// `nonisolated` — fillet/dejitter must run in MapView `Task.detached`, not MainActor.
nonisolated enum RouteCornerSmoothing: Sendable {
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

    // MARK: v5 dejitter tokens
    static let dejitterHeadingDegrees: Double = 120
    static let dejitterMaxArmMeters: CLLocationDistance = 30
    static let dejitterDefaultAccuracyMeters: CLLocationDistance = 10
    static let dejitterMaxPasses: Int = 5

    /// Diagnostics from one dejitter+smooth run (render-only; not persisted).
    struct DejitterStats: Sendable {
        var inputCount: Int = 0
        var afterDupCount: Int = 0
        var removedCount: Int = 0
        var keptCount: Int = 0
        /// Max distance of a removed point from the chord of its kept neighbors (m).
        var maxRemovedDeviationMeters: CLLocationDistance = 0
    }

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

    /// t_m = L × metersPerPoint (dump / legacy callers; subdiv uses mpp directly).
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

    // MARK: - Pause segments

    /// Split saved points by `segmentBreaks` (exclude in-pause GPS; cut at resume).
    /// Single-point chunks are returned (callers skip drawing them).
    static func pausePointSegments(
        from points: [HikingPoint],
        segmentBreaks: [HikingSegmentBreak]?
    ) -> [[HikingPoint]] {
        let filtered = HikingSessionMetrics.pointsExcludingPausedIntervals(points, segmentBreaks: segmentBreaks)
            .sorted { $0.timestamp < $1.timestamp }
        guard !filtered.isEmpty else { return [] }

        guard let breaks = segmentBreaks?.sorted(by: { $0.pauseTime < $1.pauseTime }),
              !breaks.isEmpty else {
            return [filtered]
        }

        var segments: [[HikingPoint]] = []
        var chunk: [HikingPoint] = []
        for point in filtered {
            if let last = chunk.last,
               breaks.contains(where: { segmentBreak in
                   guard let resumeTime = segmentBreak.resumeTime else { return false }
                   return last.timestamp < resumeTime && point.timestamp >= resumeTime
               }) {
                if !chunk.isEmpty { segments.append(chunk) }
                chunk = [point]
            } else {
                chunk.append(point)
            }
        }
        if !chunk.isEmpty { segments.append(chunk) }
        return segments
    }

    /// Smooth each pause-segment independently → draw layers (count≥2 only).
    static func smoothRenderSegments(
        points: [HikingPoint],
        segmentBreaks: [HikingSegmentBreak]?,
        metersPerPoint: CLLocationDistance,
        alongPt: CGFloat,
        statsOut: inout DejitterStats
    ) -> [[CLLocationCoordinate2D]] {
        var total = DejitterStats()
        var out: [[CLLocationCoordinate2D]] = []
        for seg in pausePointSegments(from: points, segmentBreaks: segmentBreaks) {
            guard seg.count >= 2 else { continue }
            var segStats = DejitterStats()
            let smoothed = smoothHikingPoints(
                seg,
                metersPerPoint: metersPerPoint,
                alongPt: alongPt,
                statsOut: &segStats
            )
            total.inputCount += segStats.inputCount
            total.afterDupCount += segStats.afterDupCount
            total.removedCount += segStats.removedCount
            total.keptCount += segStats.keptCount
            total.maxRemovedDeviationMeters = max(
                total.maxRemovedDeviationMeters,
                segStats.maxRemovedDeviationMeters
            )
            if smoothed.count >= 2 {
                out.append(smoothed)
            }
        }
        statsOut = total
        return out
    }

    static func smoothRenderSegments(
        points: [HikingPoint],
        segmentBreaks: [HikingSegmentBreak]?,
        metersPerPoint: CLLocationDistance,
        alongPt: CGFloat
    ) -> [[CLLocationCoordinate2D]] {
        var stats = DejitterStats()
        return smoothRenderSegments(
            points: points,
            segmentBreaks: segmentBreaks,
            metersPerPoint: metersPerPoint,
            alongPt: alongPt,
            statsOut: &stats
        )
    }

    static func smoothRenderSegments(
        points: [HikingPoint],
        segmentBreaks: [HikingSegmentBreak]?,
        fittingRegion: MKCoordinateRegion,
        mapWidth: CGFloat,
        mapHeight: CGFloat
    ) -> [[CLLocationCoordinate2D]] {
        let mpp = metersPerPoint(
            latitude: fittingRegion.center.latitude,
            visibleMapRect: fittingRegion.mapRect,
            boundsWidth: mapWidth
        )
        return smoothRenderSegments(
            points: points,
            segmentBreaks: segmentBreaks,
            metersPerPoint: mpp,
            alongPt: alongPt(mapWidth: mapWidth, mapHeight: mapHeight)
        )
    }

    // MARK: - Single-segment smooth

    /// Pt-space path (canvas / snapshot). Accuracies parallel to `points` (nil → default 10 m).
    static func smoothPoints(
        _ points: [CGPoint],
        metersPerUnit: CGFloat,
        metersPerScreenPoint: CGFloat,
        accuraciesMeters: [CGFloat]? = nil,
        statsOut: inout DejitterStats
    ) -> [CGPoint] {
        guard isEnabled, points.count >= 2 else {
            statsOut = DejitterStats(inputCount: points.count, keptCount: points.count)
            return points
        }
        guard metersPerUnit > 1e-18, metersPerScreenPoint > 1e-18 else { return points }

        let accIn: [CGFloat]
        if let accuraciesMeters, accuraciesMeters.count == points.count {
            accIn = accuraciesMeters.map { $0 > 0 ? $0 : CGFloat(dejitterDefaultAccuracyMeters) }
        } else {
            accIn = Array(repeating: CGFloat(dejitterDefaultAccuracyMeters), count: points.count)
        }

        var plane: [PlanePoint] = zip(points, accIn).map { PlanePoint(xy: $0.0, accuracyMeters: $0.1) }
        statsOut.inputCount = plane.count
        plane = dropNearDuplicates(plane, metersPerUnit: metersPerUnit)
        statsOut.afterDupCount = plane.count
        plane = dejitter(plane, metersPerUnit: metersPerUnit, statsOut: &statsOut)
        statsOut.keptCount = plane.count
        guard plane.count >= 2 else {
            return plane.map(\.xy)
        }
        return centripetalCatmullRomThrough(
            plane.map(\.xy),
            alpha: catmullAlpha,
            metersPerUnit: metersPerUnit,
            metersPerScreenPoint: metersPerScreenPoint
        )
    }

    static func smoothPoints(
        _ points: [CGPoint],
        metersPerUnit: CGFloat,
        metersPerScreenPoint: CGFloat,
        accuraciesMeters: [CGFloat]? = nil
    ) -> [CGPoint] {
        var stats = DejitterStats()
        return smoothPoints(
            points,
            metersPerUnit: metersPerUnit,
            metersPerScreenPoint: metersPerScreenPoint,
            accuraciesMeters: accuraciesMeters,
            statsOut: &stats
        )
    }

    /// Canvas convenience: treat pt as unit+screen scale (subdiv by pt length / 2).
    static func smoothPoints(
        _ points: [CGPoint],
        maxAlong: CGFloat
    ) -> [CGPoint] {
        _ = maxAlong
        return smoothPoints(points, metersPerUnit: 1, metersPerScreenPoint: 1)
    }

    /// Map path — coordinates only (default accuracy 10 m for dejitter).
    static func smoothCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        metersPerPoint: CLLocationDistance,
        alongPt: CGFloat
    ) -> [CLLocationCoordinate2D] {
        var stats = DejitterStats()
        return smoothCoordinates(
            coordinates,
            accuraciesMeters: nil,
            metersPerPoint: metersPerPoint,
            alongPt: alongPt,
            statsOut: &stats
        )
    }

    static func smoothCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        accuraciesMeters: [CLLocationDistance]?,
        metersPerPoint: CLLocationDistance,
        alongPt: CGFloat,
        statsOut: inout DejitterStats
    ) -> [CLLocationCoordinate2D] {
        guard isEnabled, coordinates.count >= 2 else {
            statsOut = DejitterStats(inputCount: coordinates.count, keptCount: coordinates.count)
            return coordinates
        }
        _ = alongPt
        guard metersPerPoint > 1e-12 else { return coordinates }
        let mapPoints = coordinates.map { MKMapPoint($0) }
        let midLat = coordinates[coordinates.count / 2].latitude
        let metersPerMapPoint = MKMetersPerMapPointAtLatitude(midLat)
        guard metersPerMapPoint > 1e-12 else { return coordinates }
        let raw = mapPoints.map { CGPoint(x: $0.x, y: $0.y) }
        let accCG: [CGFloat]? = accuraciesMeters.map { list in
            list.map { CGFloat($0) }
        }
        let smoothed = smoothPoints(
            raw,
            metersPerUnit: CGFloat(metersPerMapPoint),
            metersPerScreenPoint: CGFloat(metersPerPoint),
            accuraciesMeters: accCG,
            statsOut: &statsOut
        )
        return smoothed.map {
            MKMapPoint(x: Double($0.x), y: Double($0.y)).coordinate
        }
    }

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

    static func smoothHikingPoints(
        _ points: [HikingPoint],
        metersPerPoint: CLLocationDistance,
        alongPt: CGFloat,
        statsOut: inout DejitterStats
    ) -> [CLLocationCoordinate2D] {
        let coords = points.map(\.coordinate)
        let acc = points.map { $0.horizontalAccuracy ?? dejitterDefaultAccuracyMeters }
        return smoothCoordinates(
            coords,
            accuraciesMeters: acc,
            metersPerPoint: metersPerPoint,
            alongPt: alongPt,
            statsOut: &statsOut
        )
    }

    // MARK: - v5 pipeline

    private struct PlanePoint {
        var xy: CGPoint
        var accuracyMeters: CGFloat
    }

    private static func dropNearDuplicates(
        _ points: [PlanePoint],
        metersPerUnit: CGFloat
    ) -> [PlanePoint] {
        guard points.count >= 2 else { return points }
        let minSepUnits = CGFloat(duplicateMinSeparationMeters) / metersPerUnit
        var kept: [PlanePoint] = [points[0]]
        for i in 1..<(points.count - 1) {
            let p = points[i]
            let prev = kept[kept.count - 1]
            if hypot(p.xy.x - prev.xy.x, p.xy.y - prev.xy.y) >= minSepUnits {
                kept.append(p)
            }
        }
        let last = points[points.count - 1]
        if let prev = kept.last {
            if hypot(last.xy.x - prev.xy.x, last.xy.y - prev.xy.y) >= 1e-12 {
                kept.append(last)
            } else {
                kept[kept.count - 1] = last
            }
        } else {
            kept.append(last)
        }
        return kept
    }

    /// Iterative rebound removal. Preserves first/last. Max `dejitterMaxPasses`.
    private static func dejitter(
        _ points: [PlanePoint],
        metersPerUnit: CGFloat,
        statsOut: inout DejitterStats
    ) -> [PlanePoint] {
        guard points.count >= 3 else { return points }
        var current = points
        var removedDev: CGFloat = 0
        var totalRemoved = 0
        for _ in 0..<dejitterMaxPasses {
            var next: [PlanePoint] = [current[0]]
            var removedThisPass = 0
            for i in 1..<(current.count - 1) {
                let prev = next[next.count - 1] // last kept
                let p = current[i]
                let nxt = current[i + 1]
                let aUnits = hypot(p.xy.x - prev.xy.x, p.xy.y - prev.xy.y)
                let bUnits = hypot(nxt.xy.x - p.xy.x, nxt.xy.y - p.xy.y)
                let a = Double(aUnits * metersPerUnit)
                let b = Double(bUnits * metersPerUnit)
                let heading = headingDeltaDegrees(
                    from: prev.xy, via: p.xy, to: nxt.xy
                )
                let acc = Double(p.accuracyMeters)
                let drop =
                    heading > dejitterHeadingDegrees
                    && a <= dejitterMaxArmMeters
                    && b <= dejitterMaxArmMeters
                    && acc > min(a, b)
                if drop {
                    removedThisPass += 1
                    // Distance from removed point to chord prev→next (meters).
                    let cross = abs(
                        (nxt.xy.x - prev.xy.x) * (p.xy.y - prev.xy.y)
                            - (nxt.xy.y - prev.xy.y) * (p.xy.x - prev.xy.x)
                    )
                    let chord = max(hypot(nxt.xy.x - prev.xy.x, nxt.xy.y - prev.xy.y), 1e-12)
                    let devUnits = cross / chord
                    removedDev = max(removedDev, devUnits * metersPerUnit)
                } else {
                    next.append(p)
                }
            }
            next.append(current[current.count - 1])
            totalRemoved += removedThisPass
            current = next
            if removedThisPass == 0 { break }
        }
        statsOut.removedCount += totalRemoved
        statsOut.maxRemovedDeviationMeters = max(
            statsOut.maxRemovedDeviationMeters,
            CLLocationDistance(removedDev)
        )
        return current
    }

    private static func headingDeltaDegrees(from a: CGPoint, via b: CGPoint, to c: CGPoint) -> Double {
        let h1 = atan2(Double(b.y - a.y), Double(b.x - a.x))
        let h2 = atan2(Double(c.y - b.y), Double(c.x - b.x))
        var d = abs(h2 - h1) * 180 / .pi
        if d > 180 { d = 360 - d }
        return d
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
