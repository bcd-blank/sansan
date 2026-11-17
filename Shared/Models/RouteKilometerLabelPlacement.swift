//
//  RouteKilometerLabelPlacement.swift
//  Shared
//
//  Final label-placement spec v3 (summary white + detail blue).
//  Agent Store: docs/label-placement/final/spec-label-placement.md
//

#if os(iOS)

import CoreGraphics
import Foundation
import UIKit

// MARK: - Shift / request / result

struct RouteKilometerLabelShift: Equatable {
    /// Capsule center relative to the km-dot center.
    var centerOffset: CGPoint

    init(centerOffset: CGPoint) {
        self.centerOffset = centerOffset
    }

    /// Legacy L/R + vertical construction (draw fallbacks / older call sites).
    init(
        placesLabelOnLeadingSide: Bool,
        verticalOffset: CGFloat,
        capsuleWidth: CGFloat = 72,
        contentScale: CGFloat = 1
    ) {
        let gap = RouteKilometerMarkerMetrics.labelGap * contentScale
        let ox = gap + capsuleWidth / 2
        centerOffset = CGPoint(x: placesLabelOnLeadingSide ? -ox : ox, y: verticalOffset)
    }

    var placesLabelOnLeadingSide: Bool { centerOffset.x <= 0 }
    var verticalOffset: CGFloat { centerOffset.y }
}

struct RouteKilometerLabelRequest {
    let kilometer: Int
    let distanceLabel: String?
    let timeLabel: String?
    let routePoint: CGPoint
    let preferredLeadingSide: Bool
}

struct RouteKilometerPlacementResult: Equatable {
    var modeStep: Int // 1 or 5
    var shifts: [Int: RouteKilometerLabelShift]
    var stageName: String
    var nodesVisited: Int
    var elapsedMilliseconds: Double
    var partial: Bool
}

// MARK: - Solver

enum RouteKilometerLabelPlacement {
    static let sameDirCos: CGFloat = 0.3827 + 0.001
    static let nearPad: CGFloat = 32
    static let penaltyInward: CGFloat = 8
    static let penaltySameDirSoftNear: CGFloat = 6
    static let penaltySameDirSoftHard: CGFloat = 20
    static let penaltyFacing: CGFloat = 10
    static let penaltyAmbiguous: CGFloat = 8
    static let alignedPenalty: CGFloat = 0.5
    static let relaxedExtraCost: CGFloat = 6
    static let tangentWeight: CGFloat = 3
    static let nodeBudget: Int = 200_000
    /// Soft wall-clock budget for interactive detail layout (JW: idle→visible ≤ 300ms).
    /// Leave headroom under 300ms for main-thread apply after background solve.
    /// Tests may raise this to isolate correctness from the wall-clock soft cut.
    static var softTimeBudgetSeconds: CFTimeInterval = 0.28
    static let maxCandidatesPerLabel: Int = 48
    static let zoomHysteresis: Double = 0.05
    static let kmDotRadius: CGFloat = 5
    static let endpointRadius: CGFloat = 8
    static let capsuleRadius: CGFloat = 12

    enum Stage: Int, CaseIterable {
        case a, b, c, d

        var name: String {
            switch self {
            case .a: return "A"
            case .b: return "B"
            case .c: return "C"
            case .d: return "D"
            }
        }

        var distances: [CGFloat] {
            switch self {
            case .a: return [8, 12, 16]
            case .b, .c: return [8, 12, 16, 20, 24]
            case .d: return [8, 12, 16, 20, 24, 28, 32, 36]
            }
        }

        /// Stages C/D also emit relaxed-clearance candidates (+6 cost).
        var includesRelaxed: Bool { self == .c || self == .d }
    }

    struct Clearance {
        var route: CGFloat
        var pointExtra: CGFloat
        var label: CGFloat
        var ui: CGFloat
        var attribution: CGFloat

        static let strict = Clearance(route: 2, pointExtra: 2, label: 3, ui: 8, attribution: 4)
        static let relaxed = Clearance(route: 1, pointExtra: 1, label: 2, ui: 6, attribution: 3)
    }

    struct Context {
        var markers: [RouteKilometerLabelRequest]
        var endpointPoints: [CGPoint]
        var routePolyline: [CGPoint]
        var uiObstacles: [CGRect]
        var attributionBoxes: [CGRect]
        var imageSize: CGSize
        var contentScale: CGFloat
        var edgeInset: CGFloat
        var bottomInset: CGFloat
        var allowFiveKmFallback: Bool
        /// Half-width of drawn route (casing/halo outer edge) in **screen pt** before × contentScale.
        var pathHalfWidth: CGFloat
    }

    /// Per-capture collision counts in screen coordinates (pt). Complete only when all are 0.
    struct CollisionCounts: Equatable {
        var labelLabel: Int
        var labelPoint: Int
        var labelPath: Int

        var isZero: Bool { labelLabel == 0 && labelPoint == 0 && labelPath == 0 }

        var line: String {
            "label-label=\(labelLabel) label-point=\(labelPoint) label-path=\(labelPath)"
        }
    }

    // MARK: Public API

    static func placeSummary(
        markers: [RouteKilometerLabelRequest],
        endpointPoints: [CGPoint],
        routePolyline: [CGPoint] = [],
        contentScale: CGFloat,
        imageSize: CGSize,
        sideInset: CGFloat,
        pathHalfWidth: CGFloat = ShareSummaryTokens.routeCasing / 2
    ) -> RouteKilometerPlacementResult {
        let ctx = Context(
            markers: markers,
            endpointPoints: endpointPoints,
            routePolyline: routePolyline,
            uiObstacles: [],
            attributionBoxes: [],
            imageSize: imageSize,
            contentScale: contentScale,
            edgeInset: sideInset,
            bottomInset: sideInset,
            allowFiveKmFallback: true,
            pathHalfWidth: pathHalfWidth
        )
        return place(context: ctx, preferModeStep: 1, stopAfterStage: nil)
    }

    /// Detail map: caller may pass all markers; off-screen filtered here (R2).
    /// - Parameters:
    ///   - preferModeStep: last mode (1 or 5) for F4 pan hysteresis
    ///   - zoomDelta: camera zoom change since last layout (F3 when |Δ| > 0.05)
    ///   - pathHalfWidth: half of detail route stroke in screen pt (default 2.5 for 5pt stroke)
    static func placeDetail(
        markers: [RouteKilometerLabelRequest],
        endpointPoints: [CGPoint],
        routePolyline: [CGPoint] = [],
        uiObstacles: [CGRect] = [],
        contentScale: CGFloat,
        imageSize: CGSize,
        preferModeStep: Int,
        zoomDelta: Double,
        pathHalfWidth: CGFloat = 4
    ) -> RouteKilometerPlacementResult {
        let ctx = Context(
            markers: markers,
            endpointPoints: endpointPoints.filter { isOnScreen($0, size: imageSize) },
            routePolyline: routePolyline,
            uiObstacles: uiObstacles,
            attributionBoxes: [],
            imageSize: imageSize,
            contentScale: contentScale,
            edgeInset: 8,
            bottomInset: 8,
            allowFiveKmFallback: true,
            pathHalfWidth: pathHalfWidth
        )
        // F3: zoom change → always rejudge from 1km.
        if abs(zoomDelta) > zoomHysteresis {
            return place(context: ctx, preferModeStep: 1, stopAfterStage: nil)
        }
        // F4: pan-only while in 5km — return to 1km only if solvable by stage C.
        if preferModeStep >= 5 {
            let oneKm = place(context: ctx, preferModeStep: 1, stopAfterStage: .c)
            if oneKm.modeStep == 1, !oneKm.partial, oneKm.shifts.count == visibleCount(in: ctx) {
                return oneKm
            }
            return place(context: ctx, preferModeStep: 5, stopAfterStage: nil)
        }
        return place(context: ctx, preferModeStep: 1, stopAfterStage: nil)
    }

    // MARK: Core

    private static func visibleCount(in context: Context) -> Int {
        context.markers.filter { isOnScreen($0.routePoint, size: context.imageSize) }.count
    }

    private static func place(
        context: Context,
        preferModeStep: Int,
        stopAfterStage: Stage?
    ) -> RouteKilometerPlacementResult {
        let t0 = CFAbsoluteTimeGetCurrent()
        var nodes = 0
        let deadline = t0 + softTimeBudgetSeconds
        var ctx = context
        // Screen-space collision polyline (same decimate used by `auditCollisions`).
        ctx.routePolyline = collisionPolyline(context.routePolyline)
        let visible = ctx.markers.filter { isOnScreen($0.routePoint, size: ctx.imageSize) }
        guard !visible.isEmpty else {
            return result(step: 1, shifts: [:], stage: "-", nodes: 0, t0: t0, partial: false)
        }

        if preferModeStep <= 1 {
            let one = solveLadder(
                markers: visible,
                context: ctx,
                nodes: &nodes,
                stopAfter: stopAfterStage,
                deadline: deadline
            )
            if let solved = one.full {
                return result(step: 1, shifts: solved.shifts, stage: solved.stage, nodes: nodes, t0: t0, partial: false)
            }
            // F1: escalate whole screen to 5km when 5km points exist — but do not prefer a
            // 5km solution that shows *fewer* labels than the best 1km partial (JW rule③ /
            // design scenes: avoid “겹침0 via 5km만 1개” when several 1km labels fit).
            let multiples = visible.filter { $0.kilometer % 5 == 0 }
            if ctx.allowFiveKmFallback, !multiples.isEmpty {
                let five = solveLadder(
                    markers: multiples,
                    context: ctx,
                    nodes: &nodes,
                    stopAfter: nil,
                    deadline: deadline
                )
                if let solved = five.full {
                    let partialCount = one.bestPartial?.shifts.count ?? 0
                    if partialCount > solved.shifts.count {
                        let partial = one.bestPartial!
                        return result(
                            step: 1,
                            shifts: partial.shifts,
                            stage: "\(partial.stage)/prefer1",
                            nodes: nodes,
                            t0: t0,
                            partial: partial.shifts.count != visible.count
                        )
                    }
                    return result(
                        step: 5,
                        shifts: solved.shifts,
                        stage: "5/\(solved.stage)",
                        nodes: nodes,
                        t0: t0,
                        partial: false
                    )
                }
            }
            // F5: no on-screen 5km (or 5km also failed) → stage-D partial (placeable labels only).
            if let partial = one.bestPartial {
                // Soft-budget races can leave `full` nil even when every label was placed.
                let complete = partial.shifts.count == visible.count
                return result(
                    step: 1,
                    shifts: partial.shifts,
                    stage: complete ? partial.stage : "\(partial.stage)/partial",
                    nodes: nodes,
                    t0: t0,
                    partial: !complete
                )
            }
            return result(step: 1, shifts: [:], stage: "fail", nodes: nodes, t0: t0, partial: true)
        }

        // Forced 5km mode (F4 keep).
        let multiples = visible.filter { $0.kilometer % 5 == 0 }
        if multiples.isEmpty {
            let one = solveLadder(
                markers: visible,
                context: ctx,
                nodes: &nodes,
                stopAfter: nil,
                deadline: deadline
            )
            if let partial = one.bestPartial ?? one.full.map({ ($0.shifts, $0.stage) }) {
                return result(
                    step: 1,
                    shifts: partial.shifts,
                    stage: "\(partial.stage)/F5",
                    nodes: nodes,
                    t0: t0,
                    partial: one.full == nil
                )
            }
            return result(step: 1, shifts: [:], stage: "F5-empty", nodes: nodes, t0: t0, partial: true)
        }
        let five = solveLadder(
            markers: multiples,
            context: ctx,
            nodes: &nodes,
            stopAfter: nil,
            deadline: deadline
        )
        if let solved = five.full {
            return result(step: 5, shifts: solved.shifts, stage: solved.stage, nodes: nodes, t0: t0, partial: false)
        }
        if let partial = five.bestPartial {
            return result(
                step: 5,
                shifts: partial.shifts,
                stage: "\(partial.stage)/partial",
                nodes: nodes,
                t0: t0,
                partial: true
            )
        }
        return result(step: 5, shifts: [:], stage: "fail", nodes: nodes, t0: t0, partial: true)
    }

    /// Shared decimate for place + audit so clearance checks stay consistent.
    static func collisionPolyline(_ poly: [CGPoint], maxPoints: Int = 220) -> [CGPoint] {
        decimatePolyline(poly, maxPoints: maxPoints)
    }

    private static func decimatePolyline(_ poly: [CGPoint], maxPoints: Int) -> [CGPoint] {
        guard poly.count > maxPoints, maxPoints > 2 else { return poly }
        let step = Double(poly.count - 1) / Double(maxPoints - 1)
        var out: [CGPoint] = []
        out.reserveCapacity(maxPoints)
        var last = -1
        for i in 0..<maxPoints {
            let idx = min(poly.count - 1, Int((Double(i) * step).rounded()))
            if idx != last {
                out.append(poly[idx])
                last = idx
            }
        }
        if out.last != poly.last { out.append(poly.last!) }
        return out
    }

    private struct LadderOutcome {
        var full: (shifts: [Int: RouteKilometerLabelShift], stage: String)?
        var bestPartial: (shifts: [Int: RouteKilometerLabelShift], stage: String)?
    }

    private static func solveLadder(
        markers: [RouteKilometerLabelRequest],
        context: Context,
        nodes: inout Int,
        stopAfter: Stage?,
        deadline: CFAbsoluteTime
    ) -> LadderOutcome {
        var bestPartial: (shifts: [Int: RouteKilometerLabelShift], stage: String, count: Int)?
        for stage in Stage.allCases {
            if let stopAfter, stage.rawValue > stopAfter.rawValue { break }
            if nodes >= nodeBudget || CFAbsoluteTimeGetCurrent() >= deadline { break }
            var candidates = markers.map { buildCandidates(for: $0, stage: stage, context: context) }
            // Cap domains for interactive speed; keep cheapest first (already sorted).
            candidates = candidates.map { Array($0.prefix(maxCandidatesPerLabel)) }
            let greedy = greedyPlace(markers: markers, candidates: candidates, context: context, nodes: &nodes)
            if greedy.count > (bestPartial?.count ?? -1) {
                bestPartial = (greedy, stage.name, greedy.count)
            }
            if greedy.count == markers.count {
                // Prefer BnB only when small + time remains; else accept deterministic greedy.
                let remaining = deadline - CFAbsoluteTimeGetCurrent()
                if markers.count <= 8, remaining > 0.04 {
                    if let exact = solveExact(
                        markers: markers,
                        candidates: candidates,
                        context: context,
                        nodes: &nodes,
                        deadline: deadline
                    ) {
                        return LadderOutcome(
                            full: (exact, stage.name),
                            bestPartial: bestPartial.map { ($0.shifts, $0.stage) }
                        )
                    }
                }
                return LadderOutcome(
                    full: (greedy, stage.name),
                    bestPartial: bestPartial.map { ($0.shifts, $0.stage) }
                )
            }
            if nodes >= nodeBudget || CFAbsoluteTimeGetCurrent() >= deadline { break }
        }
        return LadderOutcome(full: nil, bestPartial: bestPartial.map { ($0.shifts, $0.stage) })
    }

    // MARK: Candidates

    private struct Candidate {
        var center: CGPoint
        var dir: CGVector
        var distance: CGFloat
        var isAligned: Bool
        var relaxed: Bool
        var baseCost: CGFloat
        var dirIndex: Int
        var width: CGFloat
        var height: CGFloat
    }

    private static func buildCandidates(
        for marker: RouteKilometerLabelRequest,
        stage: Stage,
        context: Context
    ) -> [Candidate] {
        let scale = context.contentScale
        let size = RouteKilometerMarkerDrawing.capsuleSize(
            distanceLabel: marker.distanceLabel,
            timeLabel: marker.timeLabel,
            contentScale: scale
        )
        let w = size.width
        let h = size.height
        guard w > 0, h > 0 else { return [] }
        let p = marker.routePoint
        let tangent = routeTangent(at: p, polyline: context.routePolyline)
        var list: [Candidate] = []

        func appendIfValid(
            center: CGPoint,
            dir: CGVector,
            distance: CGFloat,
            aligned: Bool,
            relaxed: Bool,
            dirIndex: Int
        ) {
            let clear = relaxed ? Clearance.relaxed : Clearance.strict
            let cand = Candidate(
                center: center,
                dir: dir,
                distance: distance,
                isAligned: aligned,
                relaxed: relaxed,
                baseCost: 0,
                dirIndex: dirIndex,
                width: w,
                height: h
            )
            guard passesSolo(cand, marker: marker, context: context, clear: clear) else { return }
            var c = cand
            c.baseCost = baseCost(c, tangent: tangent)
            list.append(c)
        }

        let clearancePasses: [Bool] = stage.includesRelaxed ? [false, true] : [false]
        for relaxed in clearancePasses {
            for (di, angleDeg) in stride(from: 0.0, through: 337.5, by: 22.5).enumerated() {
                let rad = CGFloat(angleDeg) * .pi / 180
                let u = CGVector(dx: cos(rad), dy: sin(rad))
                for d in stage.distances {
                    let ds = d * scale
                    guard let center = centerForDirection(
                        point: p,
                        dir: u,
                        edgeDistance: ds,
                        width: w,
                        height: h
                    ) else { continue }
                    appendIfValid(
                        center: center,
                        dir: u,
                        distance: ds,
                        aligned: false,
                        relaxed: relaxed,
                        dirIndex: di
                    )
                }
            }
            for top in [true, false] {
                for startAlign in [true, false] {
                    for d in stage.distances {
                        let ds = d * scale
                        let cx = p.x + (startAlign ? (w / 2 - capsuleRadius * scale) : -(w / 2 - capsuleRadius * scale))
                        let cy = p.y + (top ? -(ds + capsuleRadius * scale) : (ds + capsuleRadius * scale))
                        let u = CGVector(dx: 0, dy: top ? -1 : 1)
                        appendIfValid(
                            center: CGPoint(x: cx, y: cy),
                            dir: u,
                            distance: ds,
                            aligned: true,
                            relaxed: relaxed,
                            dirIndex: 100 + (top ? 0 : 2) + (startAlign ? 0 : 1)
                        )
                    }
                }
            }
        }

        list.sort {
            if $0.baseCost != $1.baseCost { return $0.baseCost < $1.baseCost }
            if $0.dirIndex != $1.dirIndex { return $0.dirIndex < $1.dirIndex }
            return $0.distance < $1.distance
        }
        return list
    }

    private static func baseCost(_ c: Candidate, tangent: CGVector) -> CGFloat {
        let along = abs(c.dir.dx * tangent.dx + c.dir.dy * tangent.dy)
        return c.distance
            + tangentWeight * along
            + (c.isAligned ? alignedPenalty : 0)
            + (c.relaxed ? relaxedExtraCost : 0)
    }

    private static func centerForDirection(
        point: CGPoint,
        dir: CGVector,
        edgeDistance: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> CGPoint? {
        var lo: CGFloat = edgeDistance
        var hi: CGFloat = edgeDistance + max(width, height)
        var best: CGPoint?
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            let center = CGPoint(x: point.x + dir.dx * mid, y: point.y + dir.dy * mid)
            let dist = outlineDistance(point: point, center: center, width: width, height: height)
            if abs(dist - edgeDistance) < 0.05 {
                return center
            }
            if dist < edgeDistance {
                lo = mid
            } else {
                hi = mid
                best = center
            }
        }
        return best ?? CGPoint(
            x: point.x + dir.dx * (edgeDistance + width / 2),
            y: point.y + dir.dy * (edgeDistance + height / 2)
        )
    }

    static func outlineDistance(point: CGPoint, center: CGPoint, width: CGFloat, height: CGFloat) -> CGFloat {
        let r = height / 2
        let a = center.x - width / 2 + r
        let b = center.x + width / 2 - r
        let cx = min(max(point.x, a), b)
        let closest = CGPoint(x: cx, y: center.y)
        return max(0, hypot(point.x - closest.x, point.y - closest.y) - r)
    }

    static func distCapsules(
        c1: CGPoint, w1: CGFloat, h1: CGFloat,
        c2: CGPoint, w2: CGFloat, h2: CGFloat
    ) -> CGFloat {
        let r1 = h1 / 2
        let r2 = h2 / 2
        let a1 = c1.x - w1 / 2 + r1
        let b1 = c1.x + w1 / 2 - r1
        let a2 = c2.x - w2 / 2 + r2
        let b2 = c2.x + w2 / 2 - r2
        let dx = max(0, max(a2 - b1, a1 - b2))
        let dy = abs(c2.y - c1.y)
        return hypot(dx, dy) - (r1 + r2)
    }

    // MARK: Solo / pair

    private static func passesSolo(
        _ cand: Candidate,
        marker: RouteKilometerLabelRequest,
        context: Context,
        clear: Clearance
    ) -> Bool {
        let scale = context.contentScale
        let rect = CGRect(
            x: cand.center.x - cand.width / 2,
            y: cand.center.y - cand.height / 2,
            width: cand.width,
            height: cand.height
        )
        let inset = context.edgeInset
        let bounds = CGRect(
            x: inset,
            y: inset,
            width: context.imageSize.width - inset - inset,
            height: context.imageSize.height - inset - context.bottomInset
        )
        if rect.minX < bounds.minX - 0.5 || rect.maxX > bounds.maxX + 0.5
            || rect.minY < bounds.minY - 0.5 || rect.maxY > bounds.maxY + 0.5 {
            return false
        }

        let ownDist = outlineDistance(
            point: marker.routePoint,
            center: cand.center,
            width: cand.width,
            height: cand.height
        )
        let ownMargin: CGFloat = (cand.distance / max(scale, 0.001)) <= 24 ? 2 * scale : 6 * scale

        for m in context.markers {
            let r = kmDotRadius * scale + clear.pointExtra * scale
            let d = outlineDistance(
                point: m.routePoint,
                center: cand.center,
                width: cand.width,
                height: cand.height
            )
            if d < r { return false }
            if m.kilometer != marker.kilometer, d < ownDist + ownMargin { return false }
        }
        for ep in context.endpointPoints {
            let r = endpointRadius * scale + clear.pointExtra * scale
            let d = outlineDistance(point: ep, center: cand.center, width: cand.width, height: cand.height)
            if d < r { return false }
            if d < ownDist + ownMargin { return false }
        }

        if !context.routePolyline.isEmpty {
            // Spec §2: screen-pt distance from path centerline to capsule ≥ pathHalf + clear.route
            // (halo/casing outer edge + extra clearance). Interior ⇒ dist 0.
            let pathClear = (context.pathHalfWidth + clear.route) * scale
            if pathHitsCapsule(
                cand: cand,
                polyline: context.routePolyline,
                clearance: pathClear
            ) {
                return false
            }
        }

        for box in context.uiObstacles {
            if rect.insetBy(dx: -clear.ui * scale, dy: -clear.ui * scale).intersects(box) { return false }
        }
        for box in context.attributionBoxes {
            if rect.insetBy(dx: -clear.attribution * scale, dy: -clear.attribution * scale).intersects(box) {
                return false
            }
        }
        return true
    }

    /// True when any polyline sample is closer than `clearance` to the capsule **solid**
    /// in screen coordinates (`outlineDistance` is 0 inside the capsule).
    private static func pathHitsCapsule(
        cand: Candidate,
        polyline: [CGPoint],
        clearance: CGFloat
    ) -> Bool {
        guard polyline.count >= 2 else { return false }
        let pad = clearance + 2
        let left = cand.center.x - cand.width / 2 - pad
        let right = cand.center.x + cand.width / 2 + pad
        let top = cand.center.y - cand.height / 2 - pad
        let bottom = cand.center.y + cand.height / 2 + pad
        let step: CGFloat = 4
        for i in 0..<(polyline.count - 1) {
            let a = polyline[i]
            let b = polyline[i + 1]
            let segMinX = min(a.x, b.x)
            let segMaxX = max(a.x, b.x)
            let segMinY = min(a.y, b.y)
            let segMaxY = max(a.y, b.y)
            if segMaxX < left || segMinX > right || segMaxY < top || segMinY > bottom { continue }
            let len = hypot(b.x - a.x, b.y - a.y)
            let n = max(1, Int(ceil(len / step)))
            for k in 0...n {
                let t = CGFloat(k) / CGFloat(n)
                let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                let d = outlineDistance(
                    point: p,
                    center: cand.center,
                    width: cand.width,
                    height: cand.height
                )
                if d < clearance { return true }
            }
        }
        return false
    }

    /// Audit placed shifts against markers/endpoints/polyline in **screen pt**.
    static func auditCollisions(
        shifts: [Int: RouteKilometerLabelShift],
        markers: [RouteKilometerLabelRequest],
        endpointPoints: [CGPoint],
        routePolyline: [CGPoint],
        contentScale: CGFloat,
        pathHalfWidth: CGFloat,
        clear: Clearance = .strict
    ) -> CollisionCounts {
        let scale = contentScale
        let placed: [(km: Int, center: CGPoint, w: CGFloat, h: CGFloat)] = markers.compactMap { m in
            guard let shift = shifts[m.kilometer] else { return nil }
            let size = RouteKilometerMarkerDrawing.capsuleSize(
                distanceLabel: m.distanceLabel,
                timeLabel: m.timeLabel,
                contentScale: contentScale
            )
            let w = size.width > 0 ? size.width : 72 * scale
            let h = size.height > 0 ? size.height : 24 * scale
            let center = CGPoint(
                x: m.routePoint.x + shift.centerOffset.x,
                y: m.routePoint.y + shift.centerOffset.y
            )
            return (m.kilometer, center, w, h)
        }
        var labelLabel = 0
        var labelPoint = 0
        var labelPath = 0
        let labelNeed = clear.label * scale
        let pointPad = clear.pointExtra * scale
        let pathNeed = (pathHalfWidth + clear.route) * scale

        for i in 0..<placed.count {
            for j in (i + 1)..<placed.count {
                let gap = distCapsules(
                    c1: placed[i].center, w1: placed[i].w, h1: placed[i].h,
                    c2: placed[j].center, w2: placed[j].w, h2: placed[j].h
                )
                if gap < labelNeed { labelLabel += 1 }
            }
        }

        let dots: [(CGPoint, CGFloat)] =
            markers.map { ($0.routePoint, kmDotRadius * scale) }
            + endpointPoints.map { ($0, endpointRadius * scale) }
        for lab in placed {
            for (p, r) in dots {
                let d = outlineDistance(point: p, center: lab.center, width: lab.w, height: lab.h)
                if d < r + pointPad { labelPoint += 1 }
            }
        }

        let poly = collisionPolyline(routePolyline)
        if poly.count >= 2 {
            for lab in placed {
                let cand = Candidate(
                    center: lab.center,
                    dir: CGVector(dx: 1, dy: 0),
                    distance: 0,
                    isAligned: false,
                    relaxed: false,
                    baseCost: 0,
                    dirIndex: 0,
                    width: lab.w,
                    height: lab.h
                )
                if pathHitsCapsule(cand: cand, polyline: poly, clearance: pathNeed) {
                    labelPath += 1
                }
            }
        }
        return CollisionCounts(labelLabel: labelLabel, labelPoint: labelPoint, labelPath: labelPath)
    }

    private static func distanceToPolyline(_ p: CGPoint, _ poly: [CGPoint]) -> CGFloat {
        guard poly.count >= 2 else { return .greatestFiniteMagnitude }
        var best = CGFloat.greatestFiniteMagnitude
        for i in 0..<(poly.count - 1) {
            best = min(best, distancePointToSegment(p, poly[i], poly[i + 1]))
        }
        return best
    }

    private static func distancePointToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let len2 = abx * abx + aby * aby
        if len2 < 1e-6 { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * abx + (p.y - a.y) * aby) / len2
        t = min(1, max(0, t))
        return hypot(p.x - (a.x + abx * t), p.y - (a.y + aby * t))
    }

    private static func routeTangent(at point: CGPoint, polyline: [CGPoint]) -> CGVector {
        guard polyline.count >= 2 else { return CGVector(dx: 1, dy: 0) }
        var bestI = 0
        var bestD = CGFloat.greatestFiniteMagnitude
        for i in 0..<polyline.count {
            let d = hypot(polyline[i].x - point.x, polyline[i].y - point.y)
            if d < bestD {
                bestD = d
                bestI = i
            }
        }
        let i0 = max(0, bestI - 1)
        let i1 = min(polyline.count - 1, bestI + 1)
        let dx = polyline[i1].x - polyline[i0].x
        let dy = polyline[i1].y - polyline[i0].y
        let len = hypot(dx, dy)
        if len < 1e-3 { return CGVector(dx: 1, dy: 0) }
        return CGVector(dx: dx / len, dy: dy / len)
    }

    private static func pairOK(
        _ a: Candidate,
        _ b: Candidate,
        markerA: RouteKilometerLabelRequest,
        markerB: RouteKilometerLabelRequest,
        clear: Clearance,
        scale: CGFloat,
        hardNeighbor: Bool
    ) -> (ok: Bool, pairCost: CGFloat) {
        let gap = distCapsules(
            c1: a.center, w1: a.width, h1: a.height,
            c2: b.center, w2: b.width, h2: b.height
        )
        if gap < clear.label * scale { return (false, 0) }
        let dot = a.dir.dx * b.dir.dx + a.dir.dy * b.dir.dy
        if hardNeighbor, dot > sameDirCos { return (false, 0) }
        var cost: CGFloat = penaltySameDirSoftNear * max(0, dot)
        if hardNeighbor {
            cost += penaltySameDirSoftHard * max(0, dot)
            let e = unit(from: markerA.routePoint, to: markerB.routePoint)
            let facingA = max(0, a.dir.dx * e.dx + a.dir.dy * e.dy)
            let facingB = max(0, b.dir.dx * (-e.dx) + b.dir.dy * (-e.dy))
            cost += penaltyFacing * min(facingA, facingB)
        }
        return (true, cost)
    }

    private static func unit(from a: CGPoint, to b: CGPoint) -> CGVector {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = hypot(dx, dy)
        if len < 1e-3 { return CGVector(dx: 1, dy: 0) }
        return CGVector(dx: dx / len, dy: dy / len)
    }

    private static func isNear(
        _ a: RouteKilometerLabelRequest,
        _ b: RouteKilometerLabelRequest,
        wa: CGFloat,
        wb: CGFloat
    ) -> Bool {
        hypot(a.routePoint.x - b.routePoint.x, a.routePoint.y - b.routePoint.y) < max(wa, wb) + nearPad
    }

    private static func isGabrielNeighbor(i: Int, j: Int, markers: [RouteKilometerLabelRequest]) -> Bool {
        let pi = markers[i].routePoint
        let pj = markers[j].routePoint
        let mx = (pi.x + pj.x) / 2
        let my = (pi.y + pj.y) / 2
        let rad = hypot(pi.x - pj.x, pi.y - pj.y) / 2
        for (k, m) in markers.enumerated() where k != i && k != j {
            if hypot(m.routePoint.x - mx, m.routePoint.y - my) < rad - 0.01 {
                return false
            }
        }
        return true
    }

    private static func labelExtraCost(
        _ cand: Candidate,
        marker: RouteKilometerLabelRequest,
        markers: [RouteKilometerLabelRequest],
        widths: [CGFloat]
    ) -> CGFloat {
        var cost: CGFloat = 0
        for (j, other) in markers.enumerated() where other.kilometer != marker.kilometer {
            if isNear(marker, other, wa: cand.width, wb: widths[j]) {
                let e = unit(from: marker.routePoint, to: other.routePoint)
                cost += penaltyInward * max(0, cand.dir.dx * e.dx + cand.dir.dy * e.dy)
            }
            let dOwnCenter = hypot(cand.center.x - marker.routePoint.x, cand.center.y - marker.routePoint.y)
            let dOtherCenter = hypot(cand.center.x - other.routePoint.x, cand.center.y - other.routePoint.y)
            if dOtherCenter + 0.01 < dOwnCenter {
                cost += penaltyAmbiguous
            }
        }
        return cost
    }

    /// Spec §5: fewer candidates first; tie → 10× → 5× → rest, then ascending km.
    private static func priorityRank(_ km: Int) -> (Int, Int) {
        let band = km % 10 == 0 ? 0 : (km % 5 == 0 ? 1 : 2)
        return (band, km)
    }

    // MARK: Search

    private static func solveExact(
        markers: [RouteKilometerLabelRequest],
        candidates: [[Candidate]],
        context: Context,
        nodes: inout Int,
        deadline: CFAbsoluteTime
    ) -> [Int: RouteKilometerLabelShift]? {
        for (i, _) in markers.enumerated() where candidates[i].isEmpty {
            return nil
        }
        if markers.count <= 10, CFAbsoluteTimeGetCurrent() < deadline {
            if let bnb = branchAndBound(
                markers: markers,
                candidates: candidates,
                context: context,
                nodes: &nodes,
                deadline: deadline
            ) {
                return bnb
            }
        }
        let g = greedyPlace(markers: markers, candidates: candidates, context: context, nodes: &nodes)
        return g.count == markers.count ? g : nil
    }

    private static func branchAndBound(
        markers: [RouteKilometerLabelRequest],
        candidates: [[Candidate]],
        context: Context,
        nodes: inout Int,
        deadline: CFAbsoluteTime
    ) -> [Int: RouteKilometerLabelShift]? {
        let n = markers.count
        let widths = markers.indices.map { candidates[$0].first?.width ?? 72 }
        var hard = Array(repeating: Array(repeating: false, count: n), count: n)
        var near = Array(repeating: Array(repeating: false, count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let isN = isNear(markers[i], markers[j], wa: widths[i], wb: widths[j])
                near[i][j] = isN
                near[j][i] = isN
                if isN, isGabrielNeighbor(i: i, j: j, markers: markers) {
                    hard[i][j] = true
                    hard[j][i] = true
                }
            }
        }

        var assignment = Array(repeating: -1, count: n)
        var assigned = Array(repeating: Candidate?.none, count: n)
        var bestAssigned: [Candidate?] = []
        var bestCost = CGFloat.greatestFiniteMagnitude

        func remainingMin(_ domains: [[Candidate]]) -> CGFloat {
            var s: CGFloat = 0
            for i in 0..<n where assignment[i] < 0 {
                s += domains[i].first?.baseCost ?? 9000
            }
            return s
        }

        func selectVar(_ domains: [[Candidate]]) -> Int? {
            var bestI: Int?
            var bestCount = Int.max
            var bestRank = (99, 99)
            for i in 0..<n where assignment[i] < 0 {
                let c = domains[i].count
                if c == 0 { return i }
                let rank = priorityRank(markers[i].kilometer)
                if c < bestCount || (c == bestCount && rank < bestRank) {
                    bestCount = c
                    bestRank = rank
                    bestI = i
                }
            }
            return bestI
        }

        func search(costSoFar: CGFloat, domains: [[Candidate]]) {
            if nodes >= nodeBudget || CFAbsoluteTimeGetCurrent() >= deadline { return }
            nodes += 1
            if costSoFar + remainingMin(domains) >= bestCost { return }
            guard let i = selectVar(domains) else {
                if costSoFar < bestCost {
                    bestCost = costSoFar
                    bestAssigned = assigned
                }
                return
            }
            if domains[i].isEmpty { return }
            for cand in domains[i] {
                if nodes >= nodeBudget || CFAbsoluteTimeGetCurrent() >= deadline { return }
                let clear: Clearance = cand.relaxed ? .relaxed : .strict
                let extra = labelExtraCost(cand, marker: markers[i], markers: markers, widths: widths)
                var pairSum: CGFloat = 0
                var compatible = true
                for j in 0..<n where assignment[j] >= 0 {
                    guard let other = assigned[j] else { continue }
                    let (ok, pc) = pairOK(
                        cand, other,
                        markerA: markers[i], markerB: markers[j],
                        clear: clear,
                        scale: context.contentScale,
                        hardNeighbor: hard[i][j]
                    )
                    if !ok { compatible = false; break }
                    if near[i][j] { pairSum += pc }
                }
                if !compatible { continue }
                let newCost = costSoFar + cand.baseCost + extra + pairSum
                if newCost >= bestCost { continue }

                var newDomains = domains
                newDomains[i] = [cand]
                var dead = false
                for j in 0..<n where assignment[j] < 0 && j != i {
                    newDomains[j] = domains[j].filter { other in
                        let (ok, _) = pairOK(
                            cand, other,
                            markerA: markers[i], markerB: markers[j],
                            clear: other.relaxed ? .relaxed : .strict,
                            scale: context.contentScale,
                            hardNeighbor: hard[i][j]
                        )
                        return ok
                    }
                    if newDomains[j].isEmpty { dead = true; break }
                }
                if dead { continue }

                assignment[i] = 0
                assigned[i] = cand
                search(costSoFar: newCost, domains: newDomains)
                assignment[i] = -1
                assigned[i] = nil
            }
        }

        search(costSoFar: 0, domains: candidates)
        guard !bestAssigned.isEmpty else { return nil }
        var shifts: [Int: RouteKilometerLabelShift] = [:]
        for i in 0..<n {
            guard let cand = bestAssigned[i] else { return nil }
            shifts[markers[i].kilometer] = RouteKilometerLabelShift(
                centerOffset: CGPoint(
                    x: cand.center.x - markers[i].routePoint.x,
                    y: cand.center.y - markers[i].routePoint.y
                )
            )
        }
        return shifts
    }

    private static func greedyPlace(
        markers: [RouteKilometerLabelRequest],
        candidates: [[Candidate]],
        context: Context,
        nodes: inout Int
    ) -> [Int: RouteKilometerLabelShift] {
        let n = markers.count
        let order = markers.indices.sorted {
            let ra = priorityRank(markers[$0].kilometer)
            let rb = priorityRank(markers[$1].kilometer)
            if ra != rb { return ra < rb }
            return markers[$0].kilometer < markers[$1].kilometer
        }
        let widths = markers.indices.map { candidates[$0].first?.width ?? 72 * context.contentScale }
        var hard = Array(repeating: Array(repeating: false, count: n), count: n)
        var near = Array(repeating: Array(repeating: false, count: n), count: n)
        for i in 0..<n {
            for j in (i + 1)..<n {
                let isN = isNear(markers[i], markers[j], wa: widths[i], wb: widths[j])
                near[i][j] = isN
                near[j][i] = isN
                if isN, isGabrielNeighbor(i: i, j: j, markers: markers) {
                    hard[i][j] = true
                    hard[j][i] = true
                }
            }
        }

        var placed: [Int: Candidate] = [:]
        var shifts: [Int: RouteKilometerLabelShift] = [:]
        for i in order {
            nodes += 1
            var best: Candidate?
            var bestScore = CGFloat.greatestFiniteMagnitude
            for cand in candidates[i] {
                nodes += 1
                let clear: Clearance = cand.relaxed ? .relaxed : .strict
                var ok = true
                var pairSum: CGFloat = 0
                for (j, other) in placed {
                    let (pairOk, pc) = pairOK(
                        cand, other,
                        markerA: markers[i], markerB: markers[j],
                        clear: clear,
                        scale: context.contentScale,
                        hardNeighbor: hard[i][j]
                    )
                    if !pairOk { ok = false; break }
                    if near[i][j] { pairSum += pc }
                }
                if !ok { continue }
                let extra = labelExtraCost(cand, marker: markers[i], markers: markers, widths: widths)
                let score = cand.baseCost + extra + pairSum
                if score < bestScore {
                    bestScore = score
                    best = cand
                }
            }
            if let best {
                placed[i] = best
                shifts[markers[i].kilometer] = RouteKilometerLabelShift(
                    centerOffset: CGPoint(
                        x: best.center.x - markers[i].routePoint.x,
                        y: best.center.y - markers[i].routePoint.y
                    )
                )
            }
        }
        return shifts
    }

    private static func result(
        step: Int,
        shifts: [Int: RouteKilometerLabelShift],
        stage: String,
        nodes: Int,
        t0: CFAbsoluteTime,
        partial: Bool
    ) -> RouteKilometerPlacementResult {
        RouteKilometerPlacementResult(
            modeStep: step,
            shifts: shifts,
            stageName: stage,
            nodesVisited: nodes,
            elapsedMilliseconds: (CFAbsoluteTimeGetCurrent() - t0) * 1000,
            partial: partial
        )
    }

    static func isOnScreen(_ point: CGPoint, size: CGSize) -> Bool {
        guard size.width > 1, size.height > 1 else { return false }
        return point.x >= 0 && point.x <= size.width && point.y >= 0 && point.y <= size.height
    }
}

#endif
