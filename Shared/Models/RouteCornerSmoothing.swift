import CoreGraphics
import CoreLocation
import Foundation
import MapKit

/// Render-only sharp-corner fillets (JW). Stored GPS / distance unchanged.
/// Tokens: `docs/design-tokens/route-corner-smooth.json` (== `route_corner_smooth.json`).
enum RouteCornerSmoothing {
    static let minTurnDegrees: CGFloat = 60
    static let filletRadiusPt: CGFloat = 4
    static let maxFilletAlongPt: CGFloat = 10
    static let arcSamples: Int = 5
    /// Map / MKMapPoint path when screen pt scale is unknown.
    static let filletRadiusMeters: CLLocationDistance = 2.5

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
        samples: Int = arcSamples
    ) -> [CGPoint] {
        guard isEnabled, points.count >= 3 else { return points }
        var out: [CGPoint] = [points[0]]
        let last = points.count - 1
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
            guard tanHalf > 1e-4 else {
                out.append(b)
                continue
            }
            let along = min(radius / tanHalf, maxAlong, abLen * 0.45, bcLen * 0.45)
            guard along > 0.35 else {
                out.append(b)
                continue
            }
            let t1 = CGPoint(x: b.x - abux * along, y: b.y - abuy * along)
            let t2 = CGPoint(x: b.x + bcux * along, y: b.y + bcuy * along)
            // Drop previous duplicate if t1 ≈ last out.
            if let prev = out.last, hypot(prev.x - t1.x, prev.y - t1.y) < 0.2 {
                out.removeLast()
            }
            out.append(t1)
            let n = max(2, samples)
            for s in 1..<n {
                let t = CGFloat(s) / CGFloat(n)
                out.append(quadratic(t1, b, t2, t: t))
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
        let maxAlong = CGFloat(max(radiusMeters * 2.5, 6) / metersPerMapPoint)
        let raw = mapPoints.map { CGPoint(x: $0.x, y: $0.y) }
        let smoothed = smoothPoints(
            raw,
            radius: radius,
            maxAlong: maxAlong,
            minTurnDegrees: minTurnDegrees,
            samples: samples
        )
        return smoothed.map {
            MKMapPoint(x: Double($0.x), y: Double($0.y)).coordinate
        }
    }

    private static func quadratic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
            y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y
        )
    }
}
