import CoreGraphics
import CoreLocation
import Foundation
import MapKit

/// Render-only sharp-corner fillets (JW). Stored GPS / distance unchanged.
/// Tokens: `docs/design-tokens/route-corner-smooth.json` (== `route_corner_smooth.json`).
///
/// **v2f:** Same input vertex array as sharp. Replace only **local-maximum** ≥30°
/// vertices with a short circularArc on the two incident segments. Every other
/// vertex stays. No whole-path densify, no cluster chord, no extended arms that
/// skip verts (v2d/v2e FAIL: GPS micro-elbows each got arcs → tipzoom zigzags).
enum RouteCornerSmoothing {
    static let minTurnDegrees: CGFloat = 30
    static let filletRadiusPt: CGFloat = 12
    static let maxFilletAlongPt: CGFloat = 12
    static let maxAlongSegmentFraction: CGFloat = 0.4
    static let arcSamples: Int = 6
    /// Short map fillet — ~12pt at 4×, not a path rewrite.
    static let filletRadiusMeters: CLLocationDistance = 2.5
    static let maxFilletAlongMeters: CLLocationDistance = 2.5
    /// Only the strongest ≥threshold elbow in this path window is filleted;
    /// weaker neighbors keep their raw vertices (no new teeth on the approach).
    static let localMaxGapMeters: CLLocationDistance = 12
    static let localMaxGapPt: CGFloat = 24

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
        let center: CGPoint
        let radius: CGFloat
        let a0: CGFloat
        let delta: CGFloat
        let along: CGFloat
    }

    static func smoothPoints(
        _ points: [CGPoint],
        radius: CGFloat = filletRadiusPt,
        maxAlong: CGFloat = maxFilletAlongPt,
        minTurnDegrees: CGFloat = minTurnDegrees,
        samples: Int = arcSamples,
        segmentFraction: CGFloat = maxAlongSegmentFraction,
        localMaxGap: CGFloat = localMaxGapPt
    ) -> [CGPoint] {
        guard isEnabled, points.count >= 3 else { return points }
        let frac = max(0.05, min(0.49, segmentFraction))
        return planAndEmit(
            points: points,
            radius: radius,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            frac: frac,
            samples: samples,
            localMaxGap: localMaxGap
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
        let maxAlong = CGFloat(maxFilletAlongMeters / metersPerMapPoint)
        let localMaxGap = CGFloat(localMaxGapMeters / metersPerMapPoint)
        let raw = mapPoints.map { CGPoint(x: $0.x, y: $0.y) }
        let smoothed = planAndEmit(
            points: raw,
            radius: radius,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            frac: maxAlongSegmentFraction,
            samples: samples,
            localMaxGap: localMaxGap
        )
        return smoothed.map {
            MKMapPoint(x: Double($0.x), y: Double($0.y)).coordinate
        }
    }

    // MARK: - Plan + emit

    private static func planAndEmit(
        points: [CGPoint],
        radius: CGFloat,
        maxAlong: CGFloat,
        minTurnDegrees: CGFloat,
        frac: CGFloat,
        samples: Int,
        localMaxGap: CGFloat
    ) -> [CGPoint] {
        let plans = planLocalMaxFillets(
            points: points,
            radius: radius,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            frac: frac,
            localMaxGap: localMaxGap
        )
        guard !plans.isEmpty else { return points }

        var planAtApex: [Int: FilletPlan] = [:]
        for plan in plans {
            planAtApex[plan.apexIndex] = plan
        }

        var out: [CGPoint] = []
        out.reserveCapacity(points.count + plans.count * samples)
        out.append(points[0])
        for i in 1..<(points.count - 1) {
            if let plan = planAtApex[i] {
                if let prev = out.last, hypot(prev.x - plan.t1.x, prev.y - plan.t1.y) < 1e-6 {
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
            } else {
                out.append(points[i])
            }
        }
        out.append(points[points.count - 1])
        return out.count >= 2 ? out : points
    }

    /// Fillet only local-maximum ≥threshold elbows. Weaker neighbors keep raw verts.
    private static func planLocalMaxFillets(
        points: [CGPoint],
        radius: CGFloat,
        maxAlong: CGFloat,
        minTurnDegrees: CGFloat,
        frac: CGFloat,
        localMaxGap: CGFloat
    ) -> [FilletPlan] {
        let last = points.count - 1
        var turns = Array(repeating: CGFloat(0), count: points.count)
        var seeds: [Int] = []
        for i in 1..<last {
            let t = adjacentTurnDegrees(points, i)
            turns[i] = t
            if t + 1e-3 >= minTurnDegrees {
                seeds.append(i)
            }
        }
        guard !seeds.isEmpty else { return [] }

        // Connected components of seeds within localMaxGap (path distance).
        var components: [[Int]] = []
        var cur: [Int] = [seeds[0]]
        for s in seeds.dropFirst() {
            if pathDistance(points, from: cur.last!, to: s) <= localMaxGap {
                cur.append(s)
            } else {
                components.append(cur)
                cur = [s]
            }
        }
        components.append(cur)

        // Per component: fillet only the geometric tip (farthest from chord through
        // the verts just outside the component). Max-turn alone suppressed curve3's
        // visual apex (idx 232) in favor of a stronger neighbor (231) → pointed tip
        // + approach kink (tipzoom FAIL).
        var tips: [Int] = []
        for comp in components {
            let first = comp.first!, lastSeed = comp.last!
            let back = max(0, first - 1)
            let fwd = min(points.count - 1, lastSeed + 1)
            if back == fwd || (comp.count == 1) {
                tips.append(comp.max(by: { turns[$0] < turns[$1] })!)
                continue
            }
            let p0 = points[back], p1 = points[fwd]
            let lx = p1.x - p0.x, ly = p1.y - p0.y
            let llen = hypot(lx, ly)
            var best = comp[0]
            var bestDist: CGFloat = -1
            for i in comp {
                let dx = points[i].x - p0.x, dy = points[i].y - p0.y
                let dist: CGFloat
                if llen < 1e-6 {
                    dist = hypot(dx, dy)
                } else {
                    dist = abs(dx * ly - dy * lx) / llen
                }
                // Prefer farther tip; tie-break by stronger turn.
                if dist > bestDist + 1e-6 || (abs(dist - bestDist) <= 1e-6 && turns[i] > turns[best]) {
                    bestDist = dist
                    best = i
                }
            }
            tips.append(best)
        }

        var reservedAlong = Array(repeating: CGFloat(0), count: points.count)
        var accepted: [FilletPlan] = []
        let ordered = tips.sorted { turns[$0] > turns[$1] }
        for i in ordered {
            guard let plan = makeAdjacentPlan(
                points: points,
                apex: i,
                turn: turns[i],
                radius: radius,
                maxAlong: maxAlong,
                frac: frac,
                reservedAlong: reservedAlong
            ) else { continue }
            accepted.append(plan)
            reservedAlong[i - 1] += plan.along
            reservedAlong[i] += plan.along
        }
        accepted.sort { $0.apexIndex < $1.apexIndex }
        return accepted
    }

    private static func makeAdjacentPlan(
        points: [CGPoint],
        apex i: Int,
        turn: CGFloat,
        radius: CGFloat,
        maxAlong: CGFloat,
        frac: CGFloat,
        reservedAlong: [CGFloat]
    ) -> FilletPlan? {
        let turnRad = turn * .pi / 180
        let half = turnRad / 2
        let tanHalf = CGFloat(tan(Double(half)))
        guard tanHalf > 1e-4 else { return nil }

        let a = points[i - 1], b = points[i], c = points[i + 1]
        let prevLen = hypot(b.x - a.x, b.y - a.y)
        let nextLen = hypot(c.x - b.x, c.y - b.y)
        guard prevLen > 1e-3, nextLen > 1e-3 else { return nil }

        let inboundFree = prevLen - reservedAlong[i - 1]
        let outboundFree = nextLen - reservedAlong[i]
        guard inboundFree > 0.5, outboundFree > 0.5 else { return nil }

        let along = min(
            radius / tanHalf,
            maxAlong,
            inboundFree * frac,
            outboundFree * frac
        )
        guard along > 0.35 else { return nil }

        let t1 = CGPoint(
            x: b.x + (a.x - b.x) * (along / prevLen),
            y: b.y + (a.y - b.y) * (along / prevLen)
        )
        let t2 = CGPoint(
            x: b.x + (c.x - b.x) * (along / nextLen),
            y: b.y + (c.y - b.y) * (along / nextLen)
        )
        let r = along * tanHalf

        let abLen = hypot(b.x - t1.x, b.y - t1.y)
        let bcLen = hypot(t2.x - b.x, t2.y - b.y)
        guard abLen > 1e-3, bcLen > 1e-3 else { return nil }
        let abux = (b.x - t1.x) / abLen
        let abuy = (b.y - t1.y) / abLen
        let bcux = (t2.x - b.x) / bcLen
        let bcuy = (t2.y - b.y) / bcLen
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
        guard abs(delta) > 1e-3 else { return nil }

        return FilletPlan(
            apexIndex: i,
            turnDegrees: turn,
            t1: t1,
            t2: t2,
            center: center,
            radius: r,
            a0: a0,
            delta: delta,
            along: along
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

    private static func pathDistance(_ points: [CGPoint], from: Int, to: Int) -> CGFloat {
        guard from != to else { return 0 }
        let lo = min(from, to), hi = max(from, to)
        var d: CGFloat = 0
        for i in lo..<hi {
            d += hypot(points[i + 1].x - points[i].x, points[i + 1].y - points[i].y)
        }
        return d
    }
}
