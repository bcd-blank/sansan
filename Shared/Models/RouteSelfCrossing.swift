import CoreLocation
import MapKit
import CoreGraphics

/// True self-crossing hits on a route polyline (later edge over earlier).
/// `nonisolated` — SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor; must run off-main in MapView.
nonisolated enum RouteSelfCrossing: Sendable {
    struct Hit: Equatable {
        /// Index of the earlier edge start vertex (`points[earlierEdge] → points[earlierEdge+1]`).
        let earlierEdge: Int
        /// Index of the later edge start vertex (`points[laterEdge] → points[laterEdge+1]`).
        let laterEdge: Int
        /// Parametric position on the later edge in `(0, 1)`.
        let u: CGFloat
        /// Crossing point in the same space as the input points.
        let point: CGPoint
    }

    struct CoordinateHit {
        let earlierEdge: Int
        let laterEdge: Int
        let u: Double
        /// Interpolated map coordinate on the later edge.
        let coordinate: CLLocationCoordinate2D
        /// Coordinates of the later overlay: starts slightly before the cross, runs to route end.
        let overlayCoordinates: [CLLocationCoordinate2D]
    }

    /// Drop near-duplicates and hairpin spikes so intersection tests stay stable.
    static func cleanedPoints(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        var cleaned: [CGPoint] = [points[0]]
        for index in 1..<points.count {
            let candidate = points[index]
            let last = cleaned[cleaned.count - 1]
            if hypot(candidate.x - last.x, candidate.y - last.y) < 0.35 { continue }
            if cleaned.count >= 2 {
                let a = cleaned[cleaned.count - 2]
                let b = last
                let abx = b.x - a.x, aby = b.y - a.y
                let bcx = candidate.x - b.x, bcy = candidate.y - b.y
                let abLen = hypot(abx, aby)
                let bcLen = hypot(bcx, bcy)
                if abLen > 0.35, bcLen > 0.35 {
                    let dot = (abx / abLen) * (bcx / bcLen) + (aby / abLen) * (bcy / bcLen)
                    if dot < -0.95 {
                        cleaned.removeLast()
                        if let newLast = cleaned.last,
                           hypot(candidate.x - newLast.x, candidate.y - newLast.y) < 0.35 {
                            continue
                        }
                    }
                }
            }
            cleaned.append(candidate)
        }
        return cleaned.count >= 2 ? cleaned : points
    }

    /// Screen/canvas-space crossings. Pass already-cleaned points; indices match that array.
    /// `minLoopLength` is in the same units as `points`.
    /// `proximityDistance`: also treat near-parallel approaches within this gap as crosses.
    /// `minProximitySin`: Android parity — proximity branch needs |sin θ| ≥ 0.28 (~12°).
    ///
    /// Perf: precompute edge lengths once; accumulate `i→j` length with `acc += d[j-1]`
    /// (never `cum[j]-cum[i]` — FP mismatch vs Android). Skip pairs whose AABBs
    /// (expanded by `proximityDistance`) do not overlap. Intersection math unchanged.
    static func hits(
        in points: [CGPoint],
        minLoopLength: CGFloat,
        minSeparationEdges: Int = 5,
        minCrossSin: CGFloat = 0.18,
        minProximitySin: CGFloat = 0.28,
        dedupeDistance: CGFloat,
        proximityDistance: CGFloat = 0
    ) -> [Hit] {
        // Do not re-clean — laterEdge must stay aligned with the caller's drawPoints.
        guard points.count >= 5 else { return [] }
        let lastEdge = points.count - 2
        // d[k] = |points[k]→points[k+1]| for k = 0…n-2 — one pass.
        var d = [CGFloat](repeating: 0, count: lastEdge + 1)
        for k in 0...lastEdge {
            let a = points[k], b = points[k + 1]
            d[k] = hypot(b.x - a.x, b.y - a.y)
        }
        let pad = max(0, proximityDistance)
        var crosses: [Hit] = []
        for i in 0...lastEdge {
            let jMin = i + max(2, minSeparationEdges)
            guard jMin <= lastEdge else { continue }
            // Outer i resets acc; each j+=1 adds d[j-1] → length i→j (same as pathLength).
            var acc: CGFloat = 0
            for j in (i + 1)...lastEdge {
                acc += d[j - 1]
                if j < jMin { continue }
                if acc < minLoopLength { continue }
                let a0 = points[i], a1 = points[i + 1]
                let b0 = points[j], b1 = points[j + 1]
                if !segmentAABBsOverlap(a0, a1, b0, b1, pad: pad) { continue }
                let sin = edgesSin(points, i: i, j: j)
                // Reject near-collinear crawls (Android shareRouteAllCrossings).
                if sin < minCrossSin { continue }
                if let hit = segmentIntersection(
                    a0, a1, b0, b1,
                    minCrossSin: minCrossSin
                ) {
                    crosses.append(Hit(earlierEdge: i, laterEdge: j, u: hit.u, point: hit.point))
                    continue
                }
                // Near-parallel proximity: ribbons visually cross even without a strict X.
                // Require steeper angle than hard X so dense curve joints do not false-hit.
                if proximityDistance > 0,
                   sin >= minProximitySin,
                   let near = segmentProximity(
                    a0, a1, b0, b1,
                    maxDistance: proximityDistance
                   ) {
                    crosses.append(Hit(earlierEdge: i, laterEdge: j, u: near.u, point: near.point))
                }
            }
        }
        crosses.sort { a, b in
            a.laterEdge < b.laterEdge || (a.laterEdge == b.laterEdge && a.u < b.u)
        }
        var unique: [Hit] = []
        for cross in crosses {
            if unique.contains(where: {
                hypot($0.point.x - cross.point.x, $0.point.y - cross.point.y) < dedupeDistance
            }) {
                continue
            }
            unique.append(cross)
        }
        return unique
    }

    /// Same as `hits` but without AABB skip — O(n²) reference to prove bbox is result-neutral.
    static func hitsWithoutAABBSkip(
        in points: [CGPoint],
        minLoopLength: CGFloat,
        minSeparationEdges: Int = 5,
        minCrossSin: CGFloat = 0.18,
        minProximitySin: CGFloat = 0.28,
        dedupeDistance: CGFloat,
        proximityDistance: CGFloat = 0
    ) -> [Hit] {
        guard points.count >= 5 else { return [] }
        let lastEdge = points.count - 2
        var d = [CGFloat](repeating: 0, count: lastEdge + 1)
        for k in 0...lastEdge {
            let a = points[k], b = points[k + 1]
            d[k] = hypot(b.x - a.x, b.y - a.y)
        }
        var crosses: [Hit] = []
        for i in 0...lastEdge {
            let jMin = i + max(2, minSeparationEdges)
            guard jMin <= lastEdge else { continue }
            var acc: CGFloat = 0
            for j in (i + 1)...lastEdge {
                acc += d[j - 1]
                if j < jMin { continue }
                if acc < minLoopLength { continue }
                let sin = edgesSin(points, i: i, j: j)
                if sin < minCrossSin { continue }
                if let hit = segmentIntersection(
                    points[i], points[i + 1],
                    points[j], points[j + 1],
                    minCrossSin: minCrossSin
                ) {
                    crosses.append(Hit(earlierEdge: i, laterEdge: j, u: hit.u, point: hit.point))
                    continue
                }
                if proximityDistance > 0,
                   sin >= minProximitySin,
                   let near = segmentProximity(
                    points[i], points[i + 1],
                    points[j], points[j + 1],
                    maxDistance: proximityDistance
                   ) {
                    crosses.append(Hit(earlierEdge: i, laterEdge: j, u: near.u, point: near.point))
                }
            }
        }
        crosses.sort { a, b in
            a.laterEdge < b.laterEdge || (a.laterEdge == b.laterEdge && a.u < b.u)
        }
        var unique: [Hit] = []
        for cross in crosses {
            if unique.contains(where: {
                hypot($0.point.x - cross.point.x, $0.point.y - cross.point.y) < dedupeDistance
            }) {
                continue
            }
            unique.append(cross)
        }
        return unique
    }

    /// Pre-optimization reference (nested `pathLength` scan). Tests only — bit-identical hits.
    static func hitsLegacyNestedPathLength(
        in points: [CGPoint],
        minLoopLength: CGFloat,
        minSeparationEdges: Int = 5,
        minCrossSin: CGFloat = 0.18,
        minProximitySin: CGFloat = 0.28,
        dedupeDistance: CGFloat,
        proximityDistance: CGFloat = 0
    ) -> [Hit] {
        guard points.count >= 5 else { return [] }
        let lastEdge = points.count - 2
        var crosses: [Hit] = []
        for i in 0...lastEdge {
            let jMin = i + max(2, minSeparationEdges)
            guard jMin <= lastEdge else { continue }
            for j in jMin...lastEdge {
                if pathLength(points, from: i, to: j) < minLoopLength { continue }
                let sin = edgesSin(points, i: i, j: j)
                if sin < minCrossSin { continue }
                if let hit = segmentIntersection(
                    points[i], points[i + 1],
                    points[j], points[j + 1],
                    minCrossSin: minCrossSin
                ) {
                    crosses.append(Hit(earlierEdge: i, laterEdge: j, u: hit.u, point: hit.point))
                    continue
                }
                if proximityDistance > 0,
                   sin >= minProximitySin,
                   let near = segmentProximity(
                    points[i], points[i + 1],
                    points[j], points[j + 1],
                    maxDistance: proximityDistance
                   ) {
                    crosses.append(Hit(earlierEdge: i, laterEdge: j, u: near.u, point: near.point))
                }
            }
        }
        crosses.sort { a, b in
            a.laterEdge < b.laterEdge || (a.laterEdge == b.laterEdge && a.u < b.u)
        }
        var unique: [Hit] = []
        for cross in crosses {
            if unique.contains(where: {
                hypot($0.point.x - cross.point.x, $0.point.y - cross.point.y) < dedupeDistance
            }) {
                continue
            }
            unique.append(cross)
        }
        return unique
    }

    /// Map-coordinate crossings using `MKMapPoint` Euclidean space.
    static func coordinateHits(
        in coordinates: [CLLocationCoordinate2D],
        minLoopMeters: CLLocationDistance = 60,
        padMeters: CLLocationDistance = 22
    ) -> [CoordinateHit] {
        guard coordinates.count >= 5 else { return [] }
        let mapPoints = coordinates.map { MKMapPoint($0) }
        let rawPoints = mapPoints.map { CGPoint(x: $0.x, y: $0.y) }
        let points = cleanedPoints(rawPoints)
        // Rebuild coordinates aligned to cleaned map points (drop hairpin/dup vertices).
        let cleanedCoords: [CLLocationCoordinate2D] = points.map {
            MKMapPoint(x: Double($0.x), y: Double($0.y)).coordinate
        }
        let mid = cleanedCoords[cleanedCoords.count / 2]
        let meterPerMapPoint = MKMetersPerMapPointAtLatitude(mid.latitude)
        let minLoop = CGFloat(minLoopMeters / max(meterPerMapPoint, 1e-9))
        let dedupe = CGFloat(12 / max(meterPerMapPoint, 1e-9))
        let raw = hits(
            in: points,
            minLoopLength: minLoop,
            minCrossSin: 0.18,
            dedupeDistance: dedupe,
            proximityDistance: CGFloat(8 / max(meterPerMapPoint, 1e-9))
        )
        let padMap = CGFloat(padMeters / max(meterPerMapPoint, 1e-9))
        return raw.compactMap { hit -> CoordinateHit? in
            let j = hit.laterEdge
            guard j + 1 < cleanedCoords.count else { return nil }
            let local = overlayPoints(
                drawPoints: points,
                hit: hit,
                backPad: padMap,
                forwardPad: padMap
            )
            guard local.count >= 2 else { return nil }
            let overlay = local.map {
                MKMapPoint(x: Double($0.x), y: Double($0.y)).coordinate
            }
            let coord = interpolate(cleanedCoords[j], cleanedCoords[j + 1], t: Double(hit.u))
            return CoordinateHit(
                earlierEdge: hit.earlierEdge,
                laterEdge: j,
                u: Double(hit.u),
                coordinate: coord,
                overlayCoordinates: overlay
            )
        }
    }

    /// Few long chronological stretches split **between** self-crosses (JW).
    /// Cut sits mid-loop so the join is far from the geometric cross; adjacent
    /// stretches share `overlapVertices` so the next round casing cap does not
    /// leave a visible seam on the previous fill. Empty hits → one continuous stretch.
    static func chronologicalPointStretches(
        points: [CGPoint],
        hits: [Hit],
        overlapVertices: Int = 4
    ) -> [[CGPoint]] {
        guard points.count >= 2 else { return [] }
        let last = points.count - 1
        let cuts = stretchCutIndices(hits: hits, lastIndex: last)
        return sliceStretches(points: points, cuts: cuts, overlapVertices: overlapVertices)
    }

    /// Map-coordinate stretches for live MapPolyline / thumbnail (same cut rule).
    static func chronologicalCoordinateStretches(
        in coordinates: [CLLocationCoordinate2D],
        minLoopMeters: CLLocationDistance = 60,
        overlapVertices: Int = 4
    ) -> [[CLLocationCoordinate2D]] {
        guard coordinates.count >= 2 else { return [] }
        guard coordinates.count >= 5 else { return [coordinates] }

        let mapPoints = coordinates.map { MKMapPoint($0) }
        let rawPoints = mapPoints.map { CGPoint(x: $0.x, y: $0.y) }
        let points = cleanedPoints(rawPoints)
        let cleanedCoords: [CLLocationCoordinate2D] = points.map {
            MKMapPoint(x: Double($0.x), y: Double($0.y)).coordinate
        }
        guard cleanedCoords.count >= 2 else { return [coordinates] }

        let mid = cleanedCoords[cleanedCoords.count / 2]
        let meterPerMapPoint = MKMetersPerMapPointAtLatitude(mid.latitude)
        let minLoop = CGFloat(minLoopMeters / max(meterPerMapPoint, 1e-9))
        let dedupe = CGFloat(12 / max(meterPerMapPoint, 1e-9))
        let proximity = CGFloat(8 / max(meterPerMapPoint, 1e-9))
        let hits = hits(
            in: points,
            minLoopLength: minLoop,
            minSeparationEdges: 2,
            minCrossSin: 0.18,
            minProximitySin: 0.28,
            dedupeDistance: dedupe,
            proximityDistance: proximity
        )
        let cuts = stretchCutIndices(hits: hits, lastIndex: cleanedCoords.count - 1)
        guard !cuts.isEmpty else { return [cleanedCoords] }
        let overlap = max(1, overlapVertices)
        let boundaries = [0] + cuts + [cleanedCoords.count - 1]
        var stretches: [[CLLocationCoordinate2D]] = []
        for index in 0..<(boundaries.count - 1) {
            var start = boundaries[index]
            let end = boundaries[index + 1]
            if index > 0 {
                start = max(0, start - overlap)
            }
            guard end > start else { continue }
            stretches.append(Array(cleanedCoords[start...end]))
        }
        let filtered = stretches.filter { $0.count >= 2 }
        return filtered.isEmpty ? [cleanedCoords] : filtered
    }

    /// Mid-loop cut indices (exclusive of 0 / last). Far from both earlier and later edges.
    static func stretchCutIndices(hits: [Hit], lastIndex: Int) -> [Int] {
        guard lastIndex >= 2 else { return [] }
        var cuts: [Int] = []
        for hit in hits {
            let span = hit.laterEdge - hit.earlierEdge
            // Need room on both sides of the mid cut so the join stays away from the cross.
            guard span >= 8 else { continue }
            let mid = hit.earlierEdge + span / 2
            let minAway = max(3, span / 4)
            guard mid - hit.earlierEdge >= minAway,
                  hit.laterEdge - mid >= minAway,
                  mid > 0,
                  mid < lastIndex
            else { continue }
            cuts.append(mid)
        }
        cuts.sort()
        var unique: [Int] = []
        for cut in cuts {
            if let last = unique.last, abs(cut - last) < 4 { continue }
            unique.append(cut)
        }
        return unique
    }

    private static func sliceStretches(
        points: [CGPoint],
        cuts: [Int],
        overlapVertices: Int
    ) -> [[CGPoint]] {
        let last = points.count - 1
        guard !cuts.isEmpty else { return [points] }
        let overlap = max(1, overlapVertices)
        let boundaries = [0] + cuts + [last]
        var stretches: [[CGPoint]] = []
        for index in 0..<(boundaries.count - 1) {
            var start = boundaries[index]
            let end = boundaries[index + 1]
            if index > 0 {
                // Overlap into previous stretch so next round casing cap sits on shared path.
                start = max(0, start - overlap)
            }
            guard end > start else { continue }
            stretches.append(Array(points[start...end]))
        }
        return stretches.filter { $0.count >= 2 }
    }

    /// Local later-ribbon bridge: `backPad` before + `forwardPad` after the cross.
    static func overlayPoints(
        drawPoints: [CGPoint],
        hit: Hit,
        backPad: CGFloat,
        forwardPad: CGFloat
    ) -> [CGPoint] {
        let j = hit.laterEdge
        guard j + 1 < drawPoints.count else { return [] }
        let b0 = drawPoints[j]
        let b1 = drawPoints[j + 1]
        let edgeLen = hypot(b1.x - b0.x, b1.y - b0.y)
        guard edgeLen > 1e-3 else { return [] }
        let along = hit.u * edgeLen

        var before: [CGPoint] = [hit.point]
        var remain = backPad
        if along > 1e-3 {
            let take = min(remain, along)
            let t = (along - take) / edgeLen
            before.append(CGPoint(
                x: b0.x + (b1.x - b0.x) * t,
                y: b0.y + (b1.y - b0.y) * t
            ))
            remain -= take
        }
        var idx = j
        while remain > 1e-3, idx > 0 {
            let p1 = drawPoints[idx]
            let p0 = drawPoints[idx - 1]
            let seg = hypot(p1.x - p0.x, p1.y - p0.y)
            if seg < 1e-3 { idx -= 1; continue }
            let take = min(remain, seg)
            let t = take / seg
            before.append(CGPoint(
                x: p1.x + (p0.x - p1.x) * t,
                y: p1.y + (p0.y - p1.y) * t
            ))
            remain -= take
            idx -= 1
            if take < seg - 1e-6 { break }
        }

        var after: [CGPoint] = []
        remain = forwardPad
        let ahead = edgeLen - along
        if ahead > 1e-3 {
            let take = min(remain, ahead)
            let t = (along + take) / edgeLen
            after.append(CGPoint(
                x: b0.x + (b1.x - b0.x) * t,
                y: b0.y + (b1.y - b0.y) * t
            ))
            remain -= take
        }
        idx = j + 1
        while remain > 1e-3, idx < drawPoints.count - 1 {
            let p0 = drawPoints[idx]
            let p1 = drawPoints[idx + 1]
            let seg = hypot(p1.x - p0.x, p1.y - p0.y)
            if seg < 1e-3 { idx += 1; continue }
            let take = min(remain, seg)
            let t = take / seg
            after.append(CGPoint(
                x: p0.x + (p1.x - p0.x) * t,
                y: p0.y + (p1.y - p0.y) * t
            ))
            remain -= take
            idx += 1
            if take < seg - 1e-6 { break }
        }

        var result: [CGPoint] = before.reversed()
        result.append(contentsOf: after)
        return result.count >= 2 ? result : []
    }

    // MARK: - Private

    private static func interpolate(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D,
        t: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    private static func pathLength(_ points: [CGPoint], from a: Int, to b: Int) -> CGFloat {
        guard b > a else { return 0 }
        var length: CGFloat = 0
        for index in a..<b {
            length += hypot(points[index + 1].x - points[index].x, points[index + 1].y - points[index].y)
        }
        return length
    }

    /// Axis-aligned bounding boxes of two segments (optional pad for proximity).
    private static func segmentAABBsOverlap(
        _ a0: CGPoint, _ a1: CGPoint,
        _ b0: CGPoint, _ b1: CGPoint,
        pad: CGFloat
    ) -> Bool {
        let aMinX = min(a0.x, a1.x) - pad
        let aMaxX = max(a0.x, a1.x) + pad
        let aMinY = min(a0.y, a1.y) - pad
        let aMaxY = max(a0.y, a1.y) + pad
        let bMinX = min(b0.x, b1.x) - pad
        let bMaxX = max(b0.x, b1.x) + pad
        let bMinY = min(b0.y, b1.y) - pad
        let bMaxY = max(b0.y, b1.y) + pad
        return aMaxX >= bMinX && bMaxX >= aMinX && aMaxY >= bMinY && bMaxY >= aMinY
    }

    private static func orient(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }

    private static func segmentIntersection(
        _ a0: CGPoint, _ a1: CGPoint,
        _ b0: CGPoint, _ b1: CGPoint,
        minCrossSin: CGFloat
    ) -> (point: CGPoint, u: CGFloat)? {
        let d1 = orient(a0, a1, b0)
        let d2 = orient(a0, a1, b1)
        let d3 = orient(b0, b1, a0)
        let d4 = orient(b0, b1, a1)
        guard d1 * d2 < 0, d3 * d4 < 0 else { return nil }
        let denom = (a1.x - a0.x) * (b1.y - b0.y) - (a1.y - a0.y) * (b1.x - b0.x)
        guard abs(denom) > 1e-6 else { return nil }
        let t = ((b0.x - a0.x) * (b1.y - b0.y) - (b0.y - a0.y) * (b1.x - b0.x)) / denom
        let u = ((b0.x - a0.x) * (a1.y - a0.y) - (b0.y - a0.y) * (a1.x - a0.x)) / denom
        // Soft interior — T merges hug endpoints (Android 0.04 / 0.96).
        guard t > 0.04, t < 0.96, u > 0.04, u < 0.96 else { return nil }
        let ax = a1.x - a0.x, ay = a1.y - a0.y
        let bx = b1.x - b0.x, by = b1.y - b0.y
        let aLen = hypot(ax, ay), bLen = hypot(bx, by)
        guard aLen > 1e-3, bLen > 1e-3 else { return nil }
        let crossMag = abs(ax * by - ay * bx) / (aLen * bLen)
        guard crossMag > minCrossSin else { return nil }
        return (
            point: CGPoint(x: b0.x + u * (b1.x - b0.x), y: b0.y + u * (b1.y - b0.y)),
            u: u
        )
    }

    /// |sin θ| of edge directions (Android `shareEdgesSin`).
    private static func edgesSin(_ points: [CGPoint], i: Int, j: Int) -> CGFloat {
        guard i + 1 < points.count, j + 1 < points.count else { return 0 }
        let ax = points[i + 1].x - points[i].x, ay = points[i + 1].y - points[i].y
        let bx = points[j + 1].x - points[j].x, by = points[j + 1].y - points[j].y
        let aLen = hypot(ax, ay), bLen = hypot(bx, by)
        guard aLen > 0.5, bLen > 0.5 else { return 0 }
        return abs(ax * by - ay * bx) / (aLen * bLen)
    }

    /// Closest approach between two segments when they nearly graze (parallel proximity).
    private static func segmentProximity(
        _ a0: CGPoint, _ a1: CGPoint,
        _ b0: CGPoint, _ b1: CGPoint,
        maxDistance: CGFloat
    ) -> (point: CGPoint, u: CGFloat)? {
        let ax = a1.x - a0.x, ay = a1.y - a0.y
        let bx = b1.x - b0.x, by = b1.y - b0.y
        let aLen = hypot(ax, ay), bLen = hypot(bx, by)
        guard aLen > 1e-3, bLen > 1e-3 else { return nil }
        // Sample a few parameters on the later edge; keep the closest mid-segment pair.
        var bestDist = CGFloat.greatestFiniteMagnitude
        var bestU: CGFloat = 0.5
        var bestT: CGFloat = 0.5
        var bestPoint = b0
        for sample in 1...8 {
            let u = CGFloat(sample) / 9
            let bp = CGPoint(x: b0.x + bx * u, y: b0.y + by * u)
            // Project bp onto earlier segment.
            let apx = bp.x - a0.x, apy = bp.y - a0.y
            let t = max(0, min(1, (apx * ax + apy * ay) / (aLen * aLen)))
            let ap = CGPoint(x: a0.x + ax * t, y: a0.y + ay * t)
            let dist = hypot(bp.x - ap.x, bp.y - ap.y)
            if dist < bestDist {
                bestDist = dist
                bestU = u
                bestT = t
                bestPoint = bp
            }
        }
        // Android shareSegmentClosest: any gap ≤ proximity counts (including near-zero
        // parallel grazes). Soft interior rejects endpoint T-merges at joints.
        guard bestDist <= maxDistance else { return nil }
        guard bestT > 0.04, bestT < 0.96, bestU > 0.04, bestU < 0.96 else { return nil }
        return (point: bestPoint, u: bestU)
    }
}
