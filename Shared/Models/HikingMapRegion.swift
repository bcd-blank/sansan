//
//  HikingMapRegion.swift
//  Shared
//

import Foundation

#if canImport(MapKit)
import MapKit

enum HikingMapRegion {
    /// 아주 짧은 경로에서 바운딩 박스가 0에 가까워지는 것만 방지(미터).
    private static let minimumBBoxMeters: Double = 60

    /// GPS 경로 좌표만으로 바운딩 MapRect를 만듭니다 (사진 좌표 제외).
    static func routeBoundingMapRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        guard !coordinates.isEmpty else { return .null }

        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        guard !rect.isNull else { return rect }

        let minDimension = MKMapPointsPerMeterAtLatitude(coordinates[0].latitude) * minimumBBoxMeters
        if rect.size.width < minDimension {
            rect = rect.insetBy(dx: -(minDimension - rect.size.width) / 2, dy: 0)
        }
        if rect.size.height < minDimension {
            rect = rect.insetBy(dx: 0, dy: -(minDimension - rect.size.height) / 2)
        }
        return rect
    }

    /// 경로 바운딩 박스가 카드 뷰포트 가로·세로의 `routeFillFraction`을 채우도록 MapRect를 계산합니다.
    static func visibleMapRect(
        for coordinates: [CLLocationCoordinate2D],
        routeFillFraction: CGFloat = HikingRouteImageLayout.routeCardFillFraction,
        fittingAspectRatio: CGFloat? = nil
    ) -> MKMapRect {
        let rect = routeBoundingMapRect(for: coordinates)
        guard !rect.isNull else { return rect }

        let fill = min(max(routeFillFraction, 0.2), 0.9)
        let minVisibleWidth = rect.size.width / fill
        let minVisibleHeight = rect.size.height / fill
        let center = MKMapPoint(x: rect.midX, y: rect.midY)

        let targetWidth: Double
        let targetHeight: Double
        if let aspect = fittingAspectRatio, aspect > 0 {
            // 카드 종횡비를 맞추되, 제한 축에서 경로가 fill 비율을 유지하도록 최소 줌만 사용.
            let height = max(minVisibleHeight, minVisibleWidth / aspect)
            targetWidth = height * aspect
            targetHeight = height
        } else {
            targetWidth = minVisibleWidth
            targetHeight = minVisibleHeight
        }

        return MKMapRect(
            x: center.x - targetWidth / 2,
            y: center.y - targetHeight / 2,
            width: targetWidth,
            height: targetHeight
        )
    }

    /// 지도 뷰 크기에 맞춰 경로 전체가 중앙에 들어가는 영역.
    static func fitting(
        coordinates: [CLLocationCoordinate2D],
        viewSize: CGSize
    ) -> MKCoordinateRegion {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return fitting(coordinates: coordinates)
        }
        let aspect = viewSize.width / viewSize.height
        let contentRect = visibleMapRect(
            for: coordinates,
            fittingAspectRatio: aspect
        )
        guard !contentRect.isNull else { return fitting(coordinates: coordinates) }
        return MKCoordinateRegion(contentRect)
    }

    /// 경로 좌표만으로 지도 영역을 계산합니다.
    static func fitting(coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let rect = visibleMapRect(for: coordinates)
        guard !rect.isNull else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
        }
        return MKCoordinateRegion(rect)
    }

    /// 스냅샷·상세 오버레이 공통 좌표 → 화면 점 변환.
    static func point(
        for coordinate: CLLocationCoordinate2D,
        in region: MKCoordinateRegion,
        canvasSize: CGSize
    ) -> CGPoint {
        let mapPoint = MKMapPoint(coordinate)
        let rect = region.mapRect
        guard rect.size.width > 0, rect.size.height > 0 else {
            return CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        }

        let x = CGFloat((mapPoint.x - rect.origin.x) / rect.size.width) * canvasSize.width
        let y = CGFloat((mapPoint.y - rect.origin.y) / rect.size.height) * canvasSize.height
        return CGPoint(x: x, y: canvasSize.height - y)
    }
}

extension MKCoordinateRegion {
    var mapRect: MKMapRect {
        let topLeft = CLLocationCoordinate2D(
            latitude: center.latitude + span.latitudeDelta / 2,
            longitude: center.longitude - span.longitudeDelta / 2
        )
        let bottomRight = CLLocationCoordinate2D(
            latitude: center.latitude - span.latitudeDelta / 2,
            longitude: center.longitude + span.longitudeDelta / 2
        )
        let a = MKMapPoint(topLeft)
        let b = MKMapPoint(bottomRight)
        return MKMapRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }
}
#endif
