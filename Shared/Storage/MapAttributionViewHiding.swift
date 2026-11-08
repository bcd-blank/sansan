//
//  MapAttributionViewHiding.swift
//  Shared
//
//  MKMapView 네이티브 Apple Maps 표기·법적 정보 서브뷰 탐지·숨김.
//

#if os(iOS)

import MapKit
import UIKit

enum MapAttributionViewHiding {
    /// MKMapView의 네이티브 법적 표기·Apple 로고 서브뷰를 찾아 숨김/복원합니다.
    @discardableResult
    static func setHidden(_ hidden: Bool, in root: UIView) -> [UIView] {
        var affected: [UIView] = []
        for view in collectAttributionViews(in: root) where view.isHidden != hidden {
            view.isHidden = hidden
            affected.append(view)
        }
        return affected
    }

    static func collectAttributionViews(in root: UIView) -> [UIView] {
        var found: [UIView] = []
        var seen = Set<ObjectIdentifier>()

        func append(_ view: UIView) {
            let id = ObjectIdentifier(view)
            guard !seen.contains(id) else { return }
            seen.insert(id)
            found.append(view)
        }

        let bounds = root.bounds
        let stripHeight = RouteMapOverlayMetrics.mkMapCaptureAttributionStripHeight(
            forMapViewWidth: max(bounds.width, 1)
        )
        let attributionZone = CGRect(
            x: 0,
            y: max(bounds.height - stripHeight - 12, 0),
            width: bounds.width * 0.62,
            height: stripHeight + 16
        )

        func walk(_ view: UIView) {
            for subview in view.subviews {
                if matchesAttributionView(subview, in: attributionZone) {
                    append(subview)
                }
                walk(subview)
            }
        }

        walk(root)
        return found
    }

    private static func matchesAttributionView(_ view: UIView, in zone: CGRect) -> Bool {
        let name = String(describing: type(of: view)).lowercased()
        if name.contains("attribution")
            || name.contains("legal")
            || name.contains("applelogo")
            || name.contains("logoimage")
            || name.contains("maplogo") {
            return true
        }

        if let label = view.accessibilityLabel?.lowercased(),
           label.contains("apple")
               || label.contains("legal")
               || label.contains("지도")
               || label.contains("maps") {
            return true
        }

        guard zone.intersects(view.frame) else { return false }

        // 좌하단 표기 스트립 안의 작은 라벨·로고·버튼.
        if view is UIControl, view.bounds.height <= zone.height + 8 {
            return true
        }

        if view is UILabel || view is UIImageView {
            return view.bounds.height <= zone.height + 4
                && view.bounds.width <= zone.width
        }

        // MKAttribution 계열 컨테이너 — 자식 UILabel만 있는 얕은 뷰.
        if view.subviews.count <= 4,
           view.bounds.height <= zone.height + 6,
           view.bounds.width <= zone.width,
           view.subviews.contains(where: { $0 is UILabel || $0 is UIImageView || $0 is UIControl }) {
            return true
        }

        return false
    }
}

#endif
