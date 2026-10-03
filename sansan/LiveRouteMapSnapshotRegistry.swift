//
//  LiveRouteMapSnapshotRegistry.swift
//  sansan
//
//  기록 상세 지도의 화면 좌표·카메라를 저장·공유 렌더에 그대로 전달합니다.
//

#if os(iOS)

import Combine
import CoreLocation
import CoreGraphics
import MapKit
import UIKit

@MainActor
final class LiveRouteMapSnapshotRegistry: ObservableObject {
    static let shared = LiveRouteMapSnapshotRegistry()

    struct Context {
        let globalFrame: CGRect
        /// SwiftUI `Map` 콘텐츠만의 화면 좌표 (오버레이·로고 제외).
        let mapContentGlobalFrame: CGRect
        let mapSize: CGSize
        let coordinates: [CLLocationCoordinate2D]
        let updatedAt: Date
    }

    struct LiveCamera {
        let region: MKCoordinateRegion
        let visibleMapRect: MKMapRect?
        let updatedAt: Date
    }

    private var contexts: [UUID: Context] = [:]
    private var liveCameras: [UUID: LiveCamera] = [:]
    private var renderViews: [UUID: WeakUIViewBox] = [:]
    private var mapViews: [UUID: WeakMKMapViewBox] = [:]
    /// 라이브 SwiftUI `Map`의 현재 보이는 영역을 캡처 시점에 즉시 계산하는 클로저.
    private var visibleRectProviders: [UUID: () -> MKMapRect?] = [:]

    private init() {}

    private final class WeakUIViewBox {
        weak var value: UIView?
        init(_ value: UIView) { self.value = value }
    }

    private final class WeakMKMapViewBox {
        weak var value: MKMapView?
        init(_ value: MKMapView) { self.value = value }
    }

    func update(
        recordID: UUID,
        globalFrame: CGRect,
        mapContentGlobalFrame: CGRect,
        mapSize: CGSize,
        coordinates: [CLLocationCoordinate2D]
    ) {
        guard mapSize.width > 1, mapSize.height > 1, globalFrame.width > 1, globalFrame.height > 1 else {
            return
        }
        let contentFrame = mapContentGlobalFrame.width > 1 && mapContentGlobalFrame.height > 1
            ? mapContentGlobalFrame
            : globalFrame
        contexts[recordID] = Context(
            globalFrame: globalFrame,
            mapContentGlobalFrame: contentFrame,
            mapSize: mapSize,
            coordinates: coordinates,
            updatedAt: Date()
        )
    }

    func updateLiveCamera(
        recordID: UUID,
        region: MKCoordinateRegion,
        visibleMapRect: MKMapRect? = nil
    ) {
        liveCameras[recordID] = LiveCamera(
            region: region,
            visibleMapRect: visibleMapRect,
            updatedAt: Date()
        )
    }

    func liveCamera(for recordID: UUID, maxAge: TimeInterval = 120) -> LiveCamera? {
        guard let camera = liveCameras[recordID] else { return nil }
        guard Date().timeIntervalSince(camera.updatedAt) <= maxAge else { return nil }
        return camera
    }

    func registerRenderView(recordID: UUID, view: UIView) {
        guard view.window != nil, view.bounds.width > 1, view.bounds.height > 1 else { return }
        renderViews[recordID] = WeakUIViewBox(view)
    }

    func registerMapView(recordID: UUID, mapView: MKMapView) {
        guard mapView.window != nil, mapView.bounds.width > 1, mapView.bounds.height > 1 else { return }
        mapViews[recordID] = WeakMKMapViewBox(mapView)
        registerRenderView(recordID: recordID, view: mapView)
        updateLiveCamera(
            recordID: recordID,
            region: mapView.region,
            visibleMapRect: mapView.visibleMapRect
        )
    }

    /// 라이브 지도의 보이는 MapRect를 캡처 시점에 즉시 산출하는 provider를 등록합니다.
    func registerVisibleRectProvider(recordID: UUID, _ provider: @escaping () -> MKMapRect?) {
        visibleRectProviders[recordID] = provider
    }

    /// 캡처 시점의 라이브 보이는 MapRect (없으면 nil).
    func liveVisibleMapRect(for recordID: UUID) -> MKMapRect? {
        guard let rect = visibleRectProviders[recordID]?(), !rect.isNull,
              rect.size.width > 0, rect.size.height > 0 else { return nil }
        return rect
    }

    func renderView(for recordID: UUID) -> UIView? {
        renderViews[recordID]?.value
    }

    func mapView(for recordID: UUID) -> MKMapView? {
        mapViews[recordID]?.value
    }

    func remove(recordID: UUID) {
        contexts[recordID] = nil
        liveCameras[recordID] = nil
        renderViews[recordID] = nil
        mapViews[recordID] = nil
        visibleRectProviders[recordID] = nil
    }

    func context(for recordID: UUID, maxAge: TimeInterval = 120) -> Context? {
        guard let context = contexts[recordID] else { return nil }
        guard Date().timeIntervalSince(context.updatedAt) <= maxAge else { return nil }
        guard context.coordinates.count >= 2 else { return nil }
        return context
    }
}

#endif
