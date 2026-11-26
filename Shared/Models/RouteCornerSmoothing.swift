import CoreGraphics
import CoreLocation
import Foundation
import MapKit

/// Render-only sharp-corner fillets (JW). Stored GPS / distance unchanged.
/// Tokens: `docs/design-tokens/route-corner-smooth.json` (== `route_corner_smooth.json`).
///
/// **v2e:** Adjacent-only short circularArc (~12pt / few meters). Same input points as
/// sharp mode; outside each fillet the centerline must match. No extended-arm /
/// cluster merge (those rewrote curve3 into a different zigzag — JW FAIL).
enum RouteCornerSmoothing {
    static let minTurnDegrees: CGFloat = 30
    static let filletRadiusPt: CGFloat = 12
    /// Cap along-leg in pt space (must stay ≈ radius, not 28).
    static let maxFilletAlongPt: CGFloat = 12
    static let maxAlongSegmentFraction: CGFloat = 0.4
    static let arcSamples: Int = 8
    /// Map-space target radius. Kept modest so 4× tipzoom still overlaps outside the fillet.
    static let filletRadiusMeters: CLLocationDistance = 4
    /// Hard cap on along-leg in meters (never treat pt constants as meters).
    static let maxFilletAlongMeters: CLLocationDistance = 4

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
        segmentFraction: CGFloat = maxAlongSegmentFraction
    ) -> [CGPoint] {
        guard isEnabled, points.count >= 3 else { return points }
        let frac = max(0.05, min(0.49, segmentFraction))
        return planAndEmit(
            points: points,
            radius: radius,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            frac: frac,
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
        let maxAlong = CGFloat(maxFilletAlongMeters / metersPerMapPoint)
        let raw = mapPoints.map { CGPoint(x: $0.x, y: $0.y) }
        let smoothed = planAndEmit(
            points: raw,
            radius: radius,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            frac: maxAlongSegmentFraction,
            samples: samples
        )
        return smoothed.map {
            MKMapPoint(x: Double($0.x), y: Double($0.y)).coordinate
        }
    }

    // MARK: - Adjacent-only plan + emit

    private static func planAndEmit(
        points: [CGPoint],
        radius: CGFloat,
        maxAlong: CGFloat,
        minTurnDegrees: CGFloat,
        frac: CGFloat,
        samples: Int
    ) -> [CGPoint] {
        let plans = planAdjacentFillets(
            points: points,
            radius: radius,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            frac: frac
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
                // Drop previous point if it coincides with t1 (short inbound leg).
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

    /// One short circularArc per adjacent ≥threshold elbow. Arms stay on the two
    /// incident segments only — never skip neighboring GPS vertices.
    private static func planAdjacentFillets(
        points: [CGPoint],
        radius: CGFloat,
        maxAlong: CGFloat,
        minTurnDegrees: CGFloat,
        frac: CGFloat
    ) -> [FilletPlan] {
        let last = points.count - 1
        var candidates: [(index: Int, turn: CGFloat)] = []
        for i in 1..<last {
            let turn = adjacentTurnDegrees(points, i)
            if turn + 1e-3 >= minTurnDegrees {
                candidates.append((i, turn))
            }
        }
        guard !candidates.isEmpty else { return [] }

        // Strongest turns first; shrink along so shared edges do not overlap.
        candidates.sort { $0.turn > $1.turn }
        var reservedAlong = Array(repeating: CGFloat(0), count: points.count)
        // reservedAlong[i] = how much of edge (i → i+1) is already claimed from either end.
        var accepted: [FilletPlan] = []

        for cand in candidates {
            let i = cand.index
            let turn = cand.turn
            let turnRad = turn * .pi / 180
            let half = turnRad / 2
            let tanHalf = CGFloat(tan(Double(half)))
            guard tanHalf > 1e-4 else { continue }

            let prevLen = hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
            let nextLen = hypot(points[i + 1].x - points[i].x, points[i + 1].y - points[i].y)
            guard prevLen > 1e-3, nextLen > 1e-3 else { continue }

            // Free length on inbound edge (i-1→i) after prior claims from i-1 end / this end.
            let inboundFree = prevLen - reservedAlong[i - 1]
            let outboundFree = nextLen - reservedAlong[i]
            guard inboundFree > 0.5, outboundFree > 0.5 else { continue }

            let along = min(
                radius / tanHalf,
                maxAlong,
                inboundFree * frac,
                outboundFree * frac
            )
            guard along > 0.35 else { continue }

            let a = points[i - 1], b = points[i], c = points[i + 1]
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
            guard abLen > 1e-3, bcLen > 1e-3 else { continue }
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
            guard abs(delta) > 1e-3 else { continue }

            accepted.append(
                FilletPlan(
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
            )
            // Claim along from the apex end of each edge.
            reservedAlong[i - 1] += along
            reservedAlong[i] += along
        }

        accepted.sort { $0.apexIndex < $1.apexIndex }
        return accepted
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
