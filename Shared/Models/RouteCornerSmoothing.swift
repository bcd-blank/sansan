import CoreGraphics
import CoreLocation
import Foundation
import MapKit

/// Render-only sharp-corner fillets (JW). Stored GPS / distance unchanged.
/// Tokens: `docs/design-tokens/route-corner-smooth.json` (== `route_corner_smooth.json`).
///
/// Uses a true circular-arc fillet (not quadratic-through-apex). Quadratic T1→apex→T2
/// hugs the tip on mid-sharp elbows (~42° / short legs) and stays visually pointed;
/// the circular cut removes the tip under the same 40% along cap.
enum RouteCornerSmoothing {
    /// v2 JW: 30° so mid-sharp GPS elbows (e.g. curve3 ~42°) fillet.
    static let minTurnDegrees: CGFloat = 30
    static let filletRadiusPt: CGFloat = 12
    static let maxFilletAlongPt: CGFloat = 28
    /// Cap fillet cut length to this fraction of each adjacent segment.
    static let maxAlongSegmentFraction: CGFloat = 0.4
    static let arcSamples: Int = 6
    /// Map path — raised from 2.5m so meter cap does not crush pt-scale fillets.
    static let filletRadiusMeters: CLLocationDistance = 8

    /// Disable via `-SANSAN_ROUTE_CORNER_SHARP` for before captures.
    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-SANSAN_ROUTE_CORNER_SHARP") { return false }
        if ProcessInfo.processInfo.environment["SANSAN_ROUTE_CORNER_SHARP"] == "1" { return false }
        return true
    }

    /// Canvas / screen-space polyline (pt).
    static func smoothPoints(
        _ points: [CGPoint],
        radius: CGFloat = filletRadiusPt,
        maxAlong: CGFloat = maxFilletAlongPt,
        minTurnDegrees: CGFloat = minTurnDegrees,
        samples: Int = arcSamples,
        segmentFraction: CGFloat = maxAlongSegmentFraction
    ) -> [CGPoint] {
        guard isEnabled, points.count >= 3 else { return points }
        var out: [CGPoint] = [points[0]]
        let last = points.count - 1
        let frac = max(0.05, min(0.49, segmentFraction))
        for i in 1..<last {
            let a = points[i - 1]
            let b = points[i]
            let c = points[i + 1]
            let abx = b.x - a.x, aby = b.y - a.y
            let bcx = c.x - b.x, bcy = c.y - b.y
            let abLen = hypot(abx, aby)
            let bcLen = hypot(bcx, bcy)
            guard abLen > 1e-3, bcLen > 1e-3 else {
                out.append(b)
                continue
            }
            let abux = abx / abLen, abuy = aby / abLen
            let bcux = bcx / bcLen, bcuy = bcy / bcLen
            let dot = max(-1, min(1, abux * bcux + abuy * bcuy))
            let turn = acos(dot) // 0 = straight, π = U-turn
            let turnDeg = turn * 180 / .pi
            guard turnDeg + 1e-3 >= minTurnDegrees, turn > 1e-3 else {
                out.append(b)
                continue
            }
            let half = turn / 2
            let tanHalf = CGFloat(tan(Double(half)))
            let sinHalf = CGFloat(sin(Double(half)))
            guard tanHalf > 1e-4, sinHalf > 1e-4 else {
                out.append(b)
                continue
            }
            // Primary cap: segment fraction (JW 40%); maxAlong is a soft ceiling in pt/map units.
            let along = min(radius / tanHalf, maxAlong, abLen * frac, bcLen * frac)
            guard along > 0.35 else {
                out.append(b)
                continue
            }
            // Effective radius after along caps (keeps G1 with circular arc).
            let r = along * tanHalf
            let t1 = CGPoint(x: b.x - abux * along, y: b.y - abuy * along)
            let t2 = CGPoint(x: b.x + bcux * along, y: b.y + bcuy * along)
            if let prev = out.last, hypot(prev.x - t1.x, prev.y - t1.y) < 0.2 {
                out.removeLast()
            }
            out.append(t1)

            // Left-of-travel normal sign from AB×BC (screen / map y-down ok — consistent).
            let cross = abux * bcuy - abuy * bcux
            let sign: CGFloat = cross >= 0 ? 1 : -1
            let n1x = -abuy * sign, n1y = abux * sign
            let center = CGPoint(x: t1.x + n1x * r, y: t1.y + n1y * r)

            let a0 = atan2(t1.y - center.y, t1.x - center.x)
            let a1 = atan2(t2.y - center.y, t2.x - center.x)
            // Sweep the short arc matching the turn (≤π).
            var delta = a1 - a0
            if sign > 0 {
                // Left turn → CCW sweep
                while delta <= 0 { delta += 2 * .pi }
                while delta > .pi + 1e-3 { delta -= 2 * .pi }
            } else {
                // Right turn → CW sweep
                while delta >= 0 { delta -= 2 * .pi }
                while delta < -(.pi + 1e-3) { delta += 2 * .pi }
            }
            let n = max(2, samples)
            for s in 1..<n {
                let t = CGFloat(s) / CGFloat(n)
                let ang = a0 + delta * t
                out.append(CGPoint(x: center.x + cos(ang) * r, y: center.y + sin(ang) * r))
            }
            out.append(t2)
        }
        out.append(points[last])
        return out.count >= 2 ? out : points
    }

    /// Map coordinates — fillet radius in meters (token `filletRadiusMeters`).
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
        // Soft ceiling in map-points: enough that 40% segment usually wins over a tiny meter cap.
        let maxAlongMeters = max(radiusMeters * 2.0, Double(maxFilletAlongPt))
        let maxAlong = CGFloat(maxAlongMeters / metersPerMapPoint)
        let raw = mapPoints.map { CGPoint(x: $0.x, y: $0.y) }
        let smoothed = smoothPoints(
            raw,
            radius: radius,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            samples: samples,
            segmentFraction: maxAlongSegmentFraction
        )
        return smoothed.map {
            MKMapPoint(x: Double($0.x), y: Double($0.y)).coordinate
        }
    }
}
