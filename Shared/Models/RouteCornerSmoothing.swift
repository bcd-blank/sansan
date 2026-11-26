import CoreGraphics
import CoreLocation
import Foundation
import MapKit

/// Render-only sharp-corner fillets (team lead final). Stored GPS / distance unchanged.
/// Tokens: `docs/design-tokens/route-corner-smooth.json` (== `route_corner_smooth.json`).
///
/// Fixed spec (both OS):
/// 1) Same draw vertex array — no simplify / resample / cluster.
/// 2) Each P(i) with adjacent turn ≥30°: A·B on the two incident segments at
///    t=min(12pt, seg×0.4); replace A→P→B with one circular arc. All other
///    verts/segments unchanged.
/// 3) Then existing stretch-split + chronological casing/fill 9/5/0.9 round.
///
/// Map path uses maxFilletAlongMeters (=12pt at curve3 tipzoom) as the t cap.
enum RouteCornerSmoothing {
    static let minTurnDegrees: CGFloat = 30
    static let maxFilletAlongPt: CGFloat = 12
    static let maxAlongSegmentFraction: CGFloat = 0.4
    static let arcSamples: Int = 5
    /// Map-space t cap = 12pt at curve3 tipzoom.
    /// Phone tipzoom: span≈32m over ≈1200pt map height → 12pt≈0.32m (not 1.2m).
    static let maxFilletAlongMeters: CLLocationDistance = 0.35
    /// Kept for token/canvas callers; arc radius is derived from along × tan(θ/2).
    static let filletRadiusPt: CGFloat = 12
    static let filletRadiusMeters: CLLocationDistance = 0.35
    /// Adjacent turn on legs shorter than this is unstable GPS noise (wrong ≥30°).
    /// Must still leave real curve3 legs (≈6.4m) eligible.
    static let minIncidentLegMeters: CLLocationDistance = 5.5

    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-SANSAN_ROUTE_CORNER_SHARP") { return false }
        if ProcessInfo.processInfo.environment["SANSAN_ROUTE_CORNER_SHARP"] == "1" { return false }
        return true
    }

    private struct FilletPlan {
        let apexIndex: Int
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
        segmentFraction: CGFloat = maxAlongSegmentFraction
    ) -> [CGPoint] {
        guard isEnabled, points.count >= 3 else { return points }
        _ = radius // arc r derived from along × tan(θ/2); kept for call-site compat
        let frac = max(0.05, min(0.49, segmentFraction))
        // pt-space: min leg ≈ maxAlong (unstable micro-edges)
        return planAndEmit(
            points: points,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            frac: frac,
            samples: samples,
            minLeg: maxAlong
        )
    }

    static func smoothCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        radiusMeters: CLLocationDistance = filletRadiusMeters,
        maxAlongMeters: CLLocationDistance = maxFilletAlongMeters,
        minTurnDegrees: CGFloat = minTurnDegrees,
        samples: Int = arcSamples
    ) -> [CLLocationCoordinate2D] {
        _ = radiusMeters
        guard isEnabled, coordinates.count >= 3 else { return coordinates }
        let mapPoints = coordinates.map { MKMapPoint($0) }
        let midLat = coordinates[coordinates.count / 2].latitude
        let metersPerMapPoint = MKMetersPerMapPointAtLatitude(midLat)
        guard metersPerMapPoint > 1e-12 else { return coordinates }
        let maxAlong = CGFloat(maxAlongMeters / metersPerMapPoint)
        let minLeg = CGFloat(minIncidentLegMeters / metersPerMapPoint)
        let raw = mapPoints.map { CGPoint(x: $0.x, y: $0.y) }
        let smoothed = planAndEmit(
            points: raw,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            frac: maxAlongSegmentFraction,
            samples: samples,
            minLeg: minLeg
        )
        return smoothed.map {
            MKMapPoint(x: Double($0.x), y: Double($0.y)).coordinate
        }
    }

    // MARK: - Plan + emit

    private static func planAndEmit(
        points: [CGPoint],
        maxAlong: CGFloat,
        minTurnDegrees: CGFloat,
        frac: CGFloat,
        samples: Int,
        minLeg: CGFloat
    ) -> [CGPoint] {
        let plans = planEverySharpVertex(
            points: points,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            frac: frac,
            minLeg: minLeg
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

    /// Every adjacent ≥30° vertex — no cluster / local-max / protrusion filter.
    /// Turn uses the two incident segment directions (correct adjacent measure).
    /// Legs shorter than minLeg are GPS micro-edges: angle is unstable and must
    /// not count as a ≥30° corner (wrong measurement on densified noise).
    private static func planEverySharpVertex(
        points: [CGPoint],
        maxAlong: CGFloat,
        minTurnDegrees: CGFloat,
        frac: CGFloat,
        minLeg: CGFloat
    ) -> [FilletPlan] {
        let last = points.count - 1
        var turns = Array(repeating: CGFloat(0), count: points.count)
        var seeds: [Int] = []
        let legMin = max(minLeg, maxAlong, 1e-3)
        for i in 1..<last {
            let a = points[i - 1], b = points[i], c = points[i + 1]
            let prevLen = hypot(b.x - a.x, b.y - a.y)
            let nextLen = hypot(c.x - b.x, c.y - b.y)
            guard prevLen + 1e-6 >= legMin, nextLen + 1e-6 >= legMin else { continue }
            let t = adjacentTurnDegrees(points, i)
            turns[i] = t
            if t + 1e-3 >= minTurnDegrees {
                seeds.append(i)
            }
        }
        guard !seeds.isEmpty else { return [] }

        var reservedAlong = Array(repeating: CGFloat(0), count: points.count)
        var accepted: [FilletPlan] = []
        // Stronger turns first so shared edges reserve fairly.
        for i in seeds.sorted(by: { turns[$0] > turns[$1] }) {
            guard let plan = makeAdjacentPlan(
                points: points,
                apex: i,
                turn: turns[i],
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

        // Spec: t = min(12pt, seg×0.4) on each incident segment.
        let along = min(maxAlong, inboundFree * frac, outboundFree * frac)
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
}
