import CoreGraphics
import CoreLocation
import Foundation
import MapKit

/// Render-only path smoothing. Stored GPS / distance must never use this array.
/// Tokens: `docs/design-tokens/route-corner-smooth.json`.
///
/// Spec (v3 — resample → Gaussian → centripetal Catmull-Rom):
/// 1. Input = one stretch of raw draw verts (cut at self-crosses by callers).
/// 2. t_m = 0.01×min(mapW,mapH)×mpp. If stretch length < 3·t_m → draw raw.
/// 3. Uniform resample by cumulative distance, step s = t_m (both endpoints).
/// 4. Gaussian σ=1.5 samples, half-width k=4 (9 taps); w_j=exp(-j²/(2·1.5²))
///    normalized; window shrinks at ends; first/last fixed to original.
/// 5. Centripetal Catmull-Rom α=0.5, 8 subdivisions/segment; duplicate ends.
/// 6. Callers feed into MKPolyline; casing/fill 9/5/0.9 round unchanged.
enum RouteCornerSmoothing {
    static let alongFractionOfMinSide: CGFloat = 0.01
    /// Canvas/pt fallback when no map size is known.
    static let maxFilletAlongPt: CGFloat = 4
    /// Skip smoothing when stretch length is shorter than this × t_m.
    static let minStretchLengthTmFactor: CGFloat = 3
    static let gaussianSigmaSamples: CGFloat = 1.5
    static let gaussianHalfWidth: Int = 4
    static let catmullAlpha: CGFloat = 0.5
    static let catmullSubdivisions: Int = 8

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

    /// Pt-space path (canvas / snapshot). `maxAlong` = t_m in the same unit as `points`.
    static func smoothPoints(
        _ points: [CGPoint],
        maxAlong: CGFloat
    ) -> [CGPoint] {
        guard isEnabled, points.count >= 2, maxAlong > 1e-9 else { return points }
        let total = pathLength(points)
        // Short stretch: skip smooth, draw raw (endpoints already raw).
        if total < minStretchLengthTmFactor * maxAlong { return points }
        let s = maxAlong // spacing = t_m
        guard s > 1e-12 else { return points }
        let resampled = resampleUniform(points, step: s)
        let gauss = gaussianSmooth(
            resampled,
            sigma: gaussianSigmaSamples,
            halfWidth: gaussianHalfWidth
        )
        return centripetalCatmullRom(
            gauss,
            alpha: catmullAlpha,
            subdivisions: catmullSubdivisions
        )
    }

    /// Map path — pass camera `metersPerPoint` and screen `alongPt` (= L).
    /// Operates in mercator map-point plane (meters via mid-lat scale).
    static func smoothCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        metersPerPoint: CLLocationDistance,
        alongPt: CGFloat
    ) -> [CLLocationCoordinate2D] {
        guard isEnabled, coordinates.count >= 2 else { return coordinates }
        let tMeters = maxAlongMeters(metersPerPoint: metersPerPoint, alongPt: alongPt)
        guard tMeters > 1e-9 else { return coordinates }
        let mapPoints = coordinates.map { MKMapPoint($0) }
        let midLat = coordinates[coordinates.count / 2].latitude
        let metersPerMapPoint = MKMetersPerMapPointAtLatitude(midLat)
        guard metersPerMapPoint > 1e-12 else { return coordinates }
        let maxAlong = CGFloat(tMeters / metersPerMapPoint)
        let raw = mapPoints.map { CGPoint(x: $0.x, y: $0.y) }
        let smoothed = smoothPoints(raw, maxAlong: maxAlong)
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

    // MARK: - v3 pipeline

    private static func pathLength(_ points: [CGPoint]) -> CGFloat {
        var total: CGFloat = 0
        for i in 1..<points.count {
            total += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
        }
        return total
    }

    /// Linear interpolate along cumulative distance at uniform step `s`. Both endpoints included.
    private static func resampleUniform(_ points: [CGPoint], step s: CGFloat) -> [CGPoint] {
        guard points.count >= 2, s > 1e-12 else { return points }
        var cum: [CGFloat] = [0]
        cum.reserveCapacity(points.count)
        for i in 1..<points.count {
            let d = hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y)
            cum.append(cum[i - 1] + d)
        }
        let total = cum[cum.count - 1]
        guard total > 1e-9 else { return [points[0], points[points.count - 1]] }

        var out: [CGPoint] = []
        out.reserveCapacity(Int(total / s) + 2)
        out.append(points[0])
        var target = s
        var seg = 0
        while target < total - 1e-9 {
            while seg < cum.count - 2, cum[seg + 1] < target {
                seg += 1
            }
            let d0 = cum[seg]
            let d1 = cum[seg + 1]
            let span = d1 - d0
            let t = span > 1e-12 ? (target - d0) / span : 0
            let a = points[seg]
            let b = points[seg + 1]
            out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            target += s
        }
        let last = points[points.count - 1]
        if let prev = out.last, hypot(prev.x - last.x, prev.y - last.y) > 1e-9 {
            out.append(last)
        } else if out.isEmpty {
            out.append(last)
        } else {
            out[out.count - 1] = last
        }
        return out
    }

    /// Gaussian smooth. σ in samples; halfWidth k → 2k+1 taps.
    /// Near ends the window shrinks symmetrically; index 0 and last stay fixed.
    private static func gaussianSmooth(
        _ points: [CGPoint],
        sigma: CGFloat,
        halfWidth k: Int
    ) -> [CGPoint] {
        let n = points.count
        guard n >= 2, k > 0, sigma > 1e-12 else { return points }
        var out = Array(repeating: CGPoint.zero, count: n)
        out[0] = points[0]
        out[n - 1] = points[n - 1]
        if n == 2 { return out }

        let twoSigmaSq = 2 * sigma * sigma
        for i in 1..<(n - 1) {
            let left = min(k, i, n - 1 - i)
            var sx: CGFloat = 0
            var sy: CGFloat = 0
            var wSum: CGFloat = 0
            for j in -left...left {
                let w = exp(-(CGFloat(j) * CGFloat(j)) / twoSigmaSq)
                let p = points[i + j]
                sx += p.x * w
                sy += p.y * w
                wSum += w
            }
            out[i] = CGPoint(x: sx / wSum, y: sy / wSum)
        }
        return out
    }

    /// Centripetal Catmull-Rom. Duplicate ends for control; `subdivisions` samples per segment
    /// (exclusive of segment start; segment end included via next segment / final append).
    private static func centripetalCatmullRom(
        _ points: [CGPoint],
        alpha: CGFloat,
        subdivisions: Int
    ) -> [CGPoint] {
        let n = points.count
        guard n >= 2, subdivisions > 0 else { return points }
        if n == 2 { return points }

        // Duplicate ends for control points.
        var ctrl = [CGPoint]()
        ctrl.reserveCapacity(n + 2)
        ctrl.append(points[0])
        ctrl.append(contentsOf: points)
        ctrl.append(points[n - 1])

        var out: [CGPoint] = []
        out.reserveCapacity((n - 1) * subdivisions + 1)
        out.append(points[0])

        for i in 1..<(ctrl.count - 2) {
            let p0 = ctrl[i - 1]
            let p1 = ctrl[i]
            let p2 = ctrl[i + 1]
            let p3 = ctrl[i + 2]
            let t0: CGFloat = 0
            let t1 = t0 + pow(max(hypot(p1.x - p0.x, p1.y - p0.y), 1e-12), alpha)
            let t2 = t1 + pow(max(hypot(p2.x - p1.x, p2.y - p1.y), 1e-12), alpha)
            let t3 = t2 + pow(max(hypot(p3.x - p2.x, p3.y - p2.y), 1e-12), alpha)
            // Sample interior of [p1,p2]: subdivisions steps → subdivisions points excluding p1,
            // including p2 only on the final segment.
            for s in 1...subdivisions {
                let u = CGFloat(s) / CGFloat(subdivisions)
                let t = t1 + (t2 - t1) * u
                let pt = catmullPoint(p0: p0, p1: p1, p2: p2, p3: p3, t0: t0, t1: t1, t2: t2, t3: t3, t: t)
                if s < subdivisions {
                    out.append(pt)
                } else if i == ctrl.count - 3 {
                    // Last segment end = original last (already fixed).
                    out.append(points[n - 1])
                } else {
                    out.append(pt)
                }
            }
        }
        // Ensure exact endpoint.
        if let last = out.last, hypot(last.x - points[n - 1].x, last.y - points[n - 1].y) > 1e-9 {
            out[out.count - 1] = points[n - 1]
        } else if out.isEmpty {
            out.append(points[n - 1])
        } else {
            out[out.count - 1] = points[n - 1]
        }
        // Ensure exact start.
        out[0] = points[0]
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
