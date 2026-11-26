import CoreGraphics
import CoreLocation
import Foundation
import MapKit

/// Render-only sharp-corner fillets (JW). Stored GPS / distance unchanged.
/// Tokens: `docs/design-tokens/route-corner-smooth.json` (== `route_corner_smooth.json`).
///
/// **v2g:** Same input as sharp. One short circularArc per tip **component**
/// (wide gap so tipzoom neighborhood has a single tip). Apex only on the two
/// incident segments; every other vertex untouched. v2f still filleted a second
/// ≥30° local-max (~26m up-leg) inside tipzoom → green bulge / new elbows.
enum RouteCornerSmoothing {
    static let minTurnDegrees: CGFloat = 30
    static let filletRadiusPt: CGFloat = 12
    static let maxFilletAlongPt: CGFloat = 12
    static let maxAlongSegmentFraction: CGFloat = 0.35
    static let arcSamples: Int = 5
    /// Short enough that tipzoom legs outside ~12pt stay pixel-identical.
    static let filletRadiusMeters: CLLocationDistance = 1.2
    static let maxFilletAlongMeters: CLLocationDistance = 1.2
    /// Wide window: one geometric tip per compound corner (curve3 228…232).
    static let localMaxGapMeters: CLLocationDistance = 45
    static let localMaxGapPt: CGFloat = 90
    /// Tip must protrude this far from the ±span chord (filters GPS micro-jogs
    /// that only become visible after densifying an arc).
    static let minTipProtrusionMeters: CLLocationDistance = 2.5
    static let tipChordSpanMeters: CLLocationDistance = 18
    static let minTipProtrusionPt: CGFloat = 8
    static let tipChordSpanPt: CGFloat = 36

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
        localMaxGap: CGFloat = localMaxGapPt,
        minTipProtrusion: CGFloat = minTipProtrusionPt,
        tipChordSpan: CGFloat = tipChordSpanPt
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
            localMaxGap: localMaxGap,
            minTipProtrusion: minTipProtrusion,
            tipChordSpan: tipChordSpan
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
        let minTip = CGFloat(minTipProtrusionMeters / metersPerMapPoint)
        let tipSpan = CGFloat(tipChordSpanMeters / metersPerMapPoint)
        let raw = mapPoints.map { CGPoint(x: $0.x, y: $0.y) }
        let smoothed = planAndEmit(
            points: raw,
            radius: radius,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            frac: maxAlongSegmentFraction,
            samples: samples,
            localMaxGap: localMaxGap,
            minTipProtrusion: minTip,
            tipChordSpan: tipSpan
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
        localMaxGap: CGFloat,
        minTipProtrusion: CGFloat,
        tipChordSpan: CGFloat
    ) -> [CGPoint] {
        let plans = planLocalMaxFillets(
            points: points,
            radius: radius,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            frac: frac,
            localMaxGap: localMaxGap,
            minTipProtrusion: minTipProtrusion,
            tipChordSpan: tipChordSpan
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

    private static func planLocalMaxFillets(
        points: [CGPoint],
        radius: CGFloat,
        maxAlong: CGFloat,
        minTurnDegrees: CGFloat,
        frac: CGFloat,
        localMaxGap: CGFloat,
        minTipProtrusion: CGFloat,
        tipChordSpan: CGFloat
    ) -> [FilletPlan] {
        let last = points.count - 1
        var turns = Array(repeating: CGFloat(0), count: points.count)
        var seeds: [Int] = []
        for i in 1..<last {
            let t = adjacentTurnDegrees(points, i)
            turns[i] = t
            guard t + 1e-3 >= minTurnDegrees else { continue }
            // Visually sharp tip only: must protrude from a longer chord.
            let protrusion = tipProtrusion(points, apex: i, span: tipChordSpan)
            guard protrusion + 1e-3 >= minTipProtrusion else { continue }
            seeds.append(i)
        }
        guard !seeds.isEmpty else { return [] }

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

        // Visual tip of a V = farthest from the midpoint of a chord that sits
        // on the long approaches *outside* the seed component. Neighbor-only
        // chords preferred idx 231 over camera tip 232 (v2f tipzoom FAIL).
        let approachPad = tipChordSpan
        var tips: [Int] = []
        for comp in components {
            let first = comp.first!, lastSeed = comp.last!
            if comp.count == 1 {
                tips.append(first)
                continue
            }
            let back = indexAtPathDistance(points, from: first, distance: -approachPad)
            let fwd = indexAtPathDistance(points, from: lastSeed, distance: approachPad)
            let p0 = points[back], p1 = points[fwd]
            let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
            var best = comp[0]
            var bestDist: CGFloat = -1
            for i in comp {
                let dist = hypot(points[i].x - mid.x, points[i].y - mid.y)
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

    /// Distance from apex to chord spanning ~`span` along-path each side.
    private static func tipProtrusion(_ points: [CGPoint], apex: Int, span: CGFloat) -> CGFloat {
        let back = indexAtPathDistance(points, from: apex, distance: -span)
        let fwd = indexAtPathDistance(points, from: apex, distance: span)
        guard back < apex, fwd > apex else { return 0 }
        let p0 = points[back], p1 = points[fwd], b = points[apex]
        let lx = p1.x - p0.x, ly = p1.y - p0.y
        let llen = hypot(lx, ly)
        guard llen > 1e-6 else { return 0 }
        return abs((b.x - p0.x) * ly - (b.y - p0.y) * lx) / llen
    }

    private static func indexAtPathDistance(_ points: [CGPoint], from: Int, distance: CGFloat) -> Int {
        if distance == 0 { return from }
        if distance < 0 {
            var left = -distance
            var i = from
            while i > 0, left > 0 {
                let step = hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
                if step >= left { return i - 1 }
                left -= step
                i -= 1
            }
            return i
        } else {
            var left = distance
            var i = from
            while i < points.count - 1, left > 0 {
                let step = hypot(points[i + 1].x - points[i].x, points[i + 1].y - points[i].y)
                if step >= left { return i + 1 }
                left -= step
                i += 1
            }
            return i
        }
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
        guard inboundFree > 0.4, outboundFree > 0.4 else { return nil }

        let along = min(
            radius / tanHalf,
            maxAlong,
            inboundFree * frac,
            outboundFree * frac
        )
        // Keep along short — tipzoom legs outside ~12pt must match.
        guard along > 0.25 else { return nil }

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
