import CoreGraphics
import CoreLocation
import Foundation
import MapKit

/// Render-only sharp-corner fillets (JW). Stored GPS / distance unchanged.
/// Tokens: `docs/design-tokens/route-corner-smooth.json` (== `route_corner_smooth.json`).
///
/// Circular-arc fillets with **extended arms** + **local cluster merge**: nearby ≥30°
/// elbows (curve3 compound tip zigzags within ~10–14pt / ~8–10m) collapse into one
/// tip-cutting arc. Cluster gap must stay local — a large gap merged curve3 with a
/// 30m-away elbow into one chord, leaving a still-pointed kink on camera.
enum RouteCornerSmoothing {
    static let minTurnDegrees: CGFloat = 30
    static let filletRadiusPt: CGFloat = 12
    static let maxFilletAlongPt: CGFloat = 28
    static let maxAlongSegmentFraction: CGFloat = 0.4
    static let arcSamples: Int = 14
    static let filletRadiusMeters: CLLocationDistance = 8
    /// Merge only compound-tip zigzags (path distance). Do not inflate with armTarget.
    static let clusterGapPt: CGFloat = 14
    /// Map-space cluster gap (meters along polyline).
    static let clusterGapMeters: CLLocationDistance = 10

    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-SANSAN_ROUTE_CORNER_SHARP") { return false }
        if ProcessInfo.processInfo.environment["SANSAN_ROUTE_CORNER_SHARP"] == "1" { return false }
        return true
    }

    private struct FilletPlan {
        let apexIndex: Int
        let turnDegrees: CGFloat
        let t1: CGPoint
        let t2: CGPoint
        let t1Outer: Int
        let t2Outer: Int
        let center: CGPoint
        let radius: CGFloat
        let a0: CGFloat
        let delta: CGFloat
    }

    static func smoothPoints(
        _ points: [CGPoint],
        radius: CGFloat = filletRadiusPt,
        maxAlong: CGFloat = maxFilletAlongPt,
        minTurnDegrees: CGFloat = minTurnDegrees,
        samples: Int = arcSamples,
        segmentFraction: CGFloat = maxAlongSegmentFraction
    ) -> [CGPoint] {
        guard isEnabled, points.count >= 3 else { return points }
        let frac = max(0.05, min(0.49, segmentFraction))
        let armTarget = max(maxAlong, radius * 2)
        // Local compound tips only — never expand to armTarget (that merged 30m elbows).
        let clusterGap = clusterGapPt
        return planAndEmit(
            points: points,
            radius: radius,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            frac: frac,
            armTarget: armTarget,
            clusterGap: clusterGap,
            samples: samples
        )
    }

    static func smoothCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        radiusMeters: CLLocationDistance = filletRadiusMeters,
        minTurnDegrees: CGFloat = minTurnDegrees,
        samples: Int = arcSamples
    ) -> [CLLocationCoordinate2D] {
        guard isEnabled, coordinates.count >= 3 else { return coordinates }
        let mapPoints = coordinates.map { MKMapPoint($0) }
        let midLat = coordinates[coordinates.count / 2].latitude
        let metersPerMapPoint = MKMetersPerMapPointAtLatitude(midLat)
        guard metersPerMapPoint > 1e-12 else { return coordinates }
        let radius = CGFloat(radiusMeters / metersPerMapPoint)
        let maxAlongMeters = max(radiusMeters * 2.5, Double(maxFilletAlongPt))
        let maxAlong = CGFloat(maxAlongMeters / metersPerMapPoint)
        let clusterGap = CGFloat(clusterGapMeters / metersPerMapPoint)
        let raw = mapPoints.map { CGPoint(x: $0.x, y: $0.y) }
        let smoothed = planAndEmit(
            points: raw,
            radius: radius,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            frac: maxAlongSegmentFraction,
            armTarget: max(maxAlong, radius * 2),
            clusterGap: clusterGap,
            samples: samples
        )
        return smoothed.map {
            MKMapPoint(x: Double($0.x), y: Double($0.y)).coordinate
        }
    }

    // MARK: - Shared plan+emit (map uses meter-scaled cluster gap)

    private static func planAndEmit(
        points: [CGPoint],
        radius: CGFloat,
        maxAlong: CGFloat,
        minTurnDegrees: CGFloat,
        frac: CGFloat,
        armTarget: CGFloat,
        clusterGap: CGFloat,
        samples: Int
    ) -> [CGPoint] {
        let plans = planFillets(
            points: points,
            radius: radius,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            frac: frac,
            armTarget: armTarget,
            clusterGap: clusterGap
        )
        guard !plans.isEmpty else { return points }
        var skip = Array(repeating: false, count: points.count)
        var planAtOuter: [Int: FilletPlan] = [:]
        for plan in plans {
            planAtOuter[plan.t1Outer] = plan
            if plan.t1Outer + 1 <= plan.t2Outer - 1 {
                for j in (plan.t1Outer + 1)...(plan.t2Outer - 1) {
                    skip[j] = true
                }
            }
        }
        var out: [CGPoint] = []
        var i = 0
        while i < points.count {
            if skip[i] { i += 1; continue }
            out.append(points[i])
            if let plan = planAtOuter[i] {
                if let prev = out.last, hypot(prev.x - plan.t1.x, prev.y - plan.t1.y) < 0.15 {
                    out.removeLast()
                }
                out.append(plan.t1)
                let n = max(2, samples)
                for s in 1..<n {
                    let t = CGFloat(s) / CGFloat(n)
                    let ang = plan.a0 + plan.delta * t
                    out.append(
                        CGPoint(
                            x: plan.center.x + cos(ang) * plan.radius,
                            y: plan.center.y + sin(ang) * plan.radius
                        )
                    )
                }
                out.append(plan.t2)
                i = plan.t2Outer
                continue
            }
            i += 1
        }
        return out.count >= 2 ? out : points
    }

    private static func planFillets(
        points: [CGPoint],
        radius: CGFloat,
        maxAlong: CGFloat,
        minTurnDegrees: CGFloat,
        frac: CGFloat,
        armTarget: CGFloat,
        clusterGap: CGFloat
    ) -> [FilletPlan] {
        let last = points.count - 1
        // Seed elbows: adjacent turn ≥ threshold.
        var seeds: [Int] = []
        for i in 1..<last {
            if adjacentTurnDegrees(points, i) + 1e-3 >= minTurnDegrees {
                seeds.append(i)
            }
        }
        guard !seeds.isEmpty else { return [] }

        // Cluster seeds within clusterGap path distance.
        var clusters: [[Int]] = []
        var current: [Int] = [seeds[0]]
        for s in seeds.dropFirst() {
            let gap = pathDistance(points, from: current.last!, to: s)
            if gap <= clusterGap {
                current.append(s)
            } else {
                clusters.append(current)
                current = [s]
            }
        }
        clusters.append(current)

        var plans: [FilletPlan] = []
        for (ci, cluster) in clusters.enumerated() {
            // Apex = member with strongest windowed turn.
            var bestIdx = cluster[0]
            var bestTurn: CGFloat = -1
            for i in cluster {
                let t = windowedTurnDegrees(points, apex: i, armTarget: armTarget)
                if t > bestTurn {
                    bestTurn = t
                    bestIdx = i
                }
            }
            guard bestTurn + 1e-3 >= minTurnDegrees else { continue }
            // Clamp arms so a neighbor seed is never swallowed into this fillet's
            // skip span (v2c/v2d bug: distant elbow chord deleted curve3 tip).
            // No neighbor → full arm to path end (synthetic single-corner tests).
            let backLimit = ci > 0
                ? max(0, (cluster.first! + clusters[ci - 1].last!) / 2)
                : 0
            let fwdLimit = ci + 1 < clusters.count
                ? min(last, (cluster.last! + clusters[ci + 1].first!) / 2)
                : last
            guard let plan = makeClusterPlan(
                points: points,
                apex: bestIdx,
                clusterFirst: cluster.first!,
                clusterLast: cluster.last!,
                radius: radius,
                maxAlong: maxAlong,
                minTurnDegrees: minTurnDegrees,
                frac: frac,
                armTarget: armTarget,
                turnDegrees: bestTurn,
                backIndexLimit: backLimit,
                fwdIndexLimit: fwdLimit
            ) else { continue }
            plans.append(plan)
        }

        // Drop overlapping plans (prefer larger turn).
        plans.sort { $0.turnDegrees > $1.turnDegrees }
        var accepted: [FilletPlan] = []
        var used = Array(repeating: false, count: points.count)
        for plan in plans {
            let lo = plan.t1Outer + 1
            let hi = plan.t2Outer - 1
            var overlap = false
            if lo <= hi {
                for j in lo...hi where used[j] { overlap = true; break }
            }
            if used[plan.apexIndex] { overlap = true }
            if overlap { continue }
            if lo <= hi {
                for j in lo...hi { used[j] = true }
            }
            used[plan.apexIndex] = true
            accepted.append(plan)
        }
        accepted.sort { $0.t1Outer < $1.t1Outer }
        return accepted
    }

    /// Fillet spanning an entire sharp cluster: T1 before first seed, T2 after last.
    private static func makeClusterPlan(
        points: [CGPoint],
        apex: Int,
        clusterFirst: Int,
        clusterLast: Int,
        radius: CGFloat,
        maxAlong: CGFloat,
        minTurnDegrees: CGFloat,
        frac: CGFloat,
        armTarget: CGFloat,
        turnDegrees: CGFloat,
        backIndexLimit: Int = 0,
        fwdIndexLimit: Int? = nil
    ) -> FilletPlan? {
        guard turnDegrees + 1e-3 >= minTurnDegrees else { return nil }
        let turnRad = turnDegrees * .pi / 180
        let half = turnRad / 2
        let tanHalf = CGFloat(tan(Double(half)))
        guard tanHalf > 1e-4 else { return nil }

        let fwdCap = fwdIndexLimit ?? (points.count - 1)
        // Edge lengths outside the cluster for the 40% cap — stop at neighbor midpoints.
        let backProbe = walk(
            points,
            from: clusterFirst,
            direction: -1,
            distance: armTarget,
            indexLimit: backIndexLimit
        )
        let fwdProbe = walk(
            points,
            from: clusterLast,
            direction: 1,
            distance: armTarget,
            indexLimit: fwdCap
        )
        guard backProbe.traveled > 0.5, fwdProbe.traveled > 0.5 else { return nil }

        let along = min(radius / tanHalf, maxAlong, backProbe.traveled * frac, fwdProbe.traveled * frac)
        guard along > 0.35 else { return nil }

        let t1Walk = walk(
            points,
            from: clusterFirst,
            direction: -1,
            distance: along,
            indexLimit: backIndexLimit
        )
        let t2Walk = walk(
            points,
            from: clusterLast,
            direction: 1,
            distance: along,
            indexLimit: fwdCap
        )
        let t1Outer = min(t1Walk.outerIndex, t1Walk.innerIndex)
        let t2Outer = max(t2Walk.outerIndex, t2Walk.innerIndex)
        guard t1Outer < clusterFirst, t2Outer > clusterLast else { return nil }

        let t1 = t1Walk.point
        let t2 = t2Walk.point
        let r = along * tanHalf

        // Tangents: along the outside edges into / out of the cluster.
        let abLen = hypot(points[clusterFirst].x - t1.x, points[clusterFirst].y - t1.y)
        let bcLen = hypot(t2.x - points[clusterLast].x, t2.y - points[clusterLast].y)
        guard abLen > 1e-3, bcLen > 1e-3 else { return nil }
        let abux = (points[clusterFirst].x - t1.x) / abLen
        let abuy = (points[clusterFirst].y - t1.y) / abLen
        let bcux = (t2.x - points[clusterLast].x) / bcLen
        let bcuy = (t2.y - points[clusterLast].y) / bcLen

        let cross = abux * bcuy - abuy * bcux
        let sign: CGFloat = cross >= 0 ? 1 : -1
        let n1x = -abuy * sign, n1y = abux * sign
        let center = CGPoint(x: t1.x + n1x * r, y: t1.y + n1y * r)
        let a0 = atan2(t1.y - center.y, t1.x - center.x)
        let a1 = atan2(t2.y - center.y, t2.x - center.x)
        var delta = a1 - a0
        if sign > 0 {
            while delta <= 0 { delta += 2 * .pi }
            while delta > .pi + 1e-3 { delta -= 2 * .pi }
        } else {
            while delta >= 0 { delta -= 2 * .pi }
            while delta < -(.pi + 1e-3) { delta += 2 * .pi }
        }

        // If the geometric arc sweep is tiny/wrong (nearly straight tangents), fall back.
        guard abs(delta) > 1e-3 else { return nil }

        return FilletPlan(
            apexIndex: apex,
            turnDegrees: turnDegrees,
            t1: t1,
            t2: t2,
            t1Outer: t1Outer,
            t2Outer: t2Outer,
            center: center,
            radius: r,
            a0: a0,
            delta: delta
        )
    }

    private static func adjacentTurnDegrees(_ points: [CGPoint], _ i: Int) -> CGFloat {
        let a = points[i - 1], b = points[i], c = points[i + 1]
        let abx = b.x - a.x, aby = b.y - a.y
        let bcx = c.x - b.x, bcy = c.y - b.y
        let abLen = hypot(abx, aby), bcLen = hypot(bcx, bcy)
        guard abLen > 1e-3, bcLen > 1e-3 else { return 0 }
        let dot = max(-1, min(1, (abx * bcx + aby * bcy) / (abLen * bcLen)))
        return acos(dot) * 180 / .pi
    }

    private static func windowedTurnDegrees(_ points: [CGPoint], apex: Int, armTarget: CGFloat) -> CGFloat {
        let b = points[apex]
        let back = walk(points, from: apex, direction: -1, distance: armTarget)
        let fwd = walk(points, from: apex, direction: 1, distance: armTarget)
        let inx = b.x - back.point.x, iny = b.y - back.point.y
        let outx = fwd.point.x - b.x, outy = fwd.point.y - b.y
        let inLen = hypot(inx, iny), outLen = hypot(outx, outy)
        guard inLen > 1e-3, outLen > 1e-3 else { return 0 }
        let dot = max(-1, min(1, (inx * outx + iny * outy) / (inLen * outLen)))
        return acos(dot) * 180 / .pi
    }

    private static func pathDistance(_ points: [CGPoint], from: Int, to: Int) -> CGFloat {
        guard from != to else { return 0 }
        let lo = min(from, to), hi = max(from, to)
        var d: CGFloat = 0
        for i in lo..<hi {
            d += hypot(points[i + 1].x - points[i].x, points[i + 1].y - points[i].y)
        }
        return d
    }

    private static func walk(
        _ points: [CGPoint],
        from index: Int,
        direction: Int,
        distance: CGFloat,
        indexLimit: Int? = nil
    ) -> (point: CGPoint, traveled: CGFloat, innerIndex: Int, outerIndex: Int) {
        var remaining = distance
        var j = index
        var traveled: CGFloat = 0
        while remaining > 1e-6 {
            let j2 = j + direction
            guard j2 >= 0, j2 < points.count else {
                return (points[j], traveled, index, j)
            }
            if let limit = indexLimit {
                if direction < 0, j2 < limit { return (points[j], traveled, index, j) }
                if direction > 0, j2 > limit { return (points[j], traveled, index, j) }
            }
            let seg = hypot(points[j2].x - points[j].x, points[j2].y - points[j].y)
            if seg <= 1e-9 {
                j = j2
                continue
            }
            if seg >= remaining - 1e-9 {
                let t = remaining / seg
                let p = CGPoint(
                    x: points[j].x + (points[j2].x - points[j].x) * t,
                    y: points[j].y + (points[j2].y - points[j].y) * t
                )
                return (p, traveled + remaining, j, j2)
            }
            remaining -= seg
            traveled += seg
            j = j2
        }
        return (points[j], traveled, index, j)
    }
}
