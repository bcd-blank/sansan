import CoreGraphics
import CoreLocation
import Foundation
import MapKit

/// Render-only corner fillets. Stored GPS / distance unchanged.
/// Tokens: `docs/design-tokens/route-corner-smooth.json`.
///
/// Spec (JW final, both OS):
/// - L = 0.01 × min(mapW, mapH) pt (e.g. 390 → 3.9pt).
/// - t_m = L × metersPerPoint(camera, lat).
/// - Every interior P(i) (skip only angle≈0): t=min(t_m, prev×0.45, next×0.45);
///   A=P−t·prevDir, B=P+t·nextDir; A→P→B quadratic Bezier (control=P), 16 samples.
/// - Outside verts/segments unchanged → stretch-split + casing/fill 9/5/0.9 round.
enum RouteCornerSmoothing {
    static let alongFractionOfMinSide: CGFloat = 0.01
    static let maxAlongSegmentFraction: CGFloat = 0.45
    static let arcSamples: Int = 16
    /// Near-colinear skip (degrees). Not a “min turn” gate — only ≈0.
    static let colinearEpsilonDegrees: CGFloat = 0.5
    /// Canvas/pt fallback when no map size is known.
    static let filletRadiusPt: CGFloat = 4
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

    private struct FilletPlan {
        let apexIndex: Int
        let apex: CGPoint
        let t1: CGPoint
        let t2: CGPoint
        let along: CGFloat
    }

    /// Pt-space path (canvas / snapshot). `maxAlong` already in the same unit as `points`.
    static func smoothPoints(
        _ points: [CGPoint],
        radius: CGFloat = filletRadiusPt,
        maxAlong: CGFloat = maxFilletAlongPt,
        minTurnDegrees: CGFloat = colinearEpsilonDegrees,
        samples: Int = arcSamples,
        segmentFraction: CGFloat = maxAlongSegmentFraction
    ) -> [CGPoint] {
        guard isEnabled, points.count >= 3 else { return points }
        _ = radius
        let frac = max(0.05, min(0.49, segmentFraction))
        return planAndEmit(
            points: points,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            frac: frac,
            samples: samples
        )
    }

    /// Map path — pass camera `metersPerPoint` and screen `alongPt` (= L).
    static func smoothCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        metersPerPoint: CLLocationDistance,
        alongPt: CGFloat,
        samples: Int = arcSamples
    ) -> [CLLocationCoordinate2D] {
        guard isEnabled, coordinates.count >= 3 else { return coordinates }
        let tMeters = maxAlongMeters(metersPerPoint: metersPerPoint, alongPt: alongPt)
        guard tMeters > 1e-9 else { return coordinates }
        let mapPoints = coordinates.map { MKMapPoint($0) }
        let midLat = coordinates[coordinates.count / 2].latitude
        let metersPerMapPoint = MKMetersPerMapPointAtLatitude(midLat)
        guard metersPerMapPoint > 1e-12 else { return coordinates }
        let maxAlong = CGFloat(tMeters / metersPerMapPoint)
        let raw = mapPoints.map { CGPoint(x: $0.x, y: $0.y) }
        let smoothed = planAndEmit(
            points: raw,
            maxAlong: maxAlong,
            minTurnDegrees: colinearEpsilonDegrees,
            frac: maxAlongSegmentFraction,
            samples: samples
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
        mapHeight: CGFloat,
        samples: Int = arcSamples
    ) -> [CLLocationCoordinate2D] {
        let mpp = metersPerPoint(
            latitude: fittingRegion.center.latitude,
            visibleMapRect: fittingRegion.mapRect,
            boundsWidth: mapWidth
        )
        return smoothCoordinates(
            coordinates,
            metersPerPoint: mpp,
            alongPt: alongPt(mapWidth: mapWidth, mapHeight: mapHeight),
            samples: samples
        )
    }

    // MARK: - Plan + emit

    private static func planAndEmit(
        points: [CGPoint],
        maxAlong: CGFloat,
        minTurnDegrees: CGFloat,
        frac: CGFloat,
        samples: Int
    ) -> [CGPoint] {
        let plans = planEveryInteriorVertex(
            points: points,
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
                if let prev = out.last, hypot(prev.x - plan.t1.x, prev.y - plan.t1.y) < 1e-9 {
                    out.removeLast()
                }
                out.append(plan.t1)
                let n = max(2, samples)
                let p = plan.apex
                for s in 1..<n {
                    let u = CGFloat(s) / CGFloat(n)
                    let omu = 1 - u
                    out.append(
                        CGPoint(
                            x: omu * omu * plan.t1.x + 2 * omu * u * p.x + u * u * plan.t2.x,
                            y: omu * omu * plan.t1.y + 2 * omu * u * p.y + u * u * plan.t2.y
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

    /// Every interior vertex except near-colinear (angle≈0).
    private static func planEveryInteriorVertex(
        points: [CGPoint],
        maxAlong: CGFloat,
        minTurnDegrees: CGFloat,
        frac: CGFloat
    ) -> [FilletPlan] {
        let last = points.count - 1
        var turns = Array(repeating: CGFloat(0), count: points.count)
        var seeds: [Int] = []
        for i in 1..<last {
            let t = adjacentTurnDegrees(points, i)
            turns[i] = t
            if t + 1e-6 > minTurnDegrees {
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
        maxAlong: CGFloat,
        frac: CGFloat,
        reservedAlong: [CGFloat]
    ) -> FilletPlan? {
        let a = points[i - 1], b = points[i], c = points[i + 1]
        let prevLen = hypot(b.x - a.x, b.y - a.y)
        let nextLen = hypot(c.x - b.x, c.y - b.y)
        guard prevLen > 1e-9, nextLen > 1e-9 else { return nil }

        let inboundFree = prevLen - reservedAlong[i - 1]
        let outboundFree = nextLen - reservedAlong[i]
        guard inboundFree > 0, outboundFree > 0 else { return nil }

        // t = min(t_m, prev×0.45, next×0.45)
        let along = min(maxAlong, inboundFree * frac, outboundFree * frac)
        guard along > 1e-9 else { return nil }

        // prevDir = (P−A)/|P−A|, nextDir = (C−P)/|C−P|
        // A' = P − t·prevDir, B' = P + t·nextDir
        let prevDirX = (b.x - a.x) / prevLen
        let prevDirY = (b.y - a.y) / prevLen
        let nextDirX = (c.x - b.x) / nextLen
        let nextDirY = (c.y - b.y) / nextLen
        let t1 = CGPoint(x: b.x - prevDirX * along, y: b.y - prevDirY * along)
        let t2 = CGPoint(x: b.x + nextDirX * along, y: b.y + nextDirY * along)
        return FilletPlan(apexIndex: i, apex: b, t1: t1, t2: t2, along: along)
    }

    private static func adjacentTurnDegrees(_ points: [CGPoint], _ i: Int) -> CGFloat {
        let a = points[i - 1], b = points[i], c = points[i + 1]
        let abx = b.x - a.x, aby = b.y - a.y
        let bcx = c.x - b.x, bcy = c.y - b.y
        let abLen = hypot(abx, aby), bcLen = hypot(bcx, bcy)
        guard abLen > 1e-9, bcLen > 1e-9 else { return 0 }
        let dot = max(-1, min(1, (abx * bcx + aby * bcy) / (abLen * bcLen)))
        return acos(dot) * 180 / .pi
    }
}
