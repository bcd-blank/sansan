//
//  RouteMapVisibleRenderRegistrar.swift
//  sansan
//
//  상세 SwiftUI Map의 Metal 렌더 뷰를 등록해 화면에 그려진 타일(녹지)을 캡처합니다.
//

#if os(iOS)

import MapKit
import QuartzCore
import SwiftUI
import UIKit

struct RouteMapVisibleRenderRegistrar: UIViewRepresentable {
    let recordID: UUID

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.recordID = recordID
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ uiView: AnchorView, context: Context) {
        uiView.recordID = recordID
        uiView.scheduleRegistrationIfNeeded()
    }

    final class AnchorView: UIView {
        var recordID: UUID?
        private var pendingRegistration: DispatchWorkItem?
        private var registeredRecordID: UUID?

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleRegistrationIfNeeded()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                pendingRegistration?.cancel()
                registeredRecordID = nil
                return
            }
            scheduleRegistrationIfNeeded()
        }

        func scheduleRegistrationIfNeeded() {
            guard window != nil else { return }
            guard registeredRecordID != recordID else { return }

            pendingRegistration?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.registerIfNeeded()
            }
            pendingRegistration = work
            DispatchQueue.main.async(execute: work)
        }

        private func registerIfNeeded() {
            guard let recordID, window != nil else { return }
            if registeredRecordID == recordID,
               LiveRouteMapSnapshotRegistry.shared.mapView(for: recordID) != nil {
                return
            }

            if let mapView = MapViewLocator.findMKMapView(around: self) {
                LiveRouteMapSnapshotRegistry.shared.registerMapView(recordID: recordID, mapView: mapView)
                registeredRecordID = recordID
                return
            }

            guard let host = resolveMapRenderHost() else { return }
            LiveRouteMapSnapshotRegistry.shared.registerRenderView(recordID: recordID, view: host)
            registeredRecordID = recordID
        }

        private func resolveMapRenderHost() -> UIView? {
            guard let superview else { return nil }

            if let metalHost = MapMetalLayerLocator.deepestViewWithMetalLayer(in: superview),
               metalHost.bounds.width > 1,
               metalHost.bounds.height > 1 {
                return metalHost
            }

            let siblings = superview.subviews.filter { subview in
                subview !== self && !subview.isHidden && subview.alpha > 0.01
            }
            if let largest = siblings.max(by: {
                $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height
            }), largest.bounds.width > 1, largest.bounds.height > 1 {
                return largest
            }

            return superview
        }
    }
}

enum MapViewLocator {
    static func findMKMapView(around view: UIView) -> MKMapView? {
        var candidate: UIView? = view
        while let current = candidate {
            if let mapView = searchMKMapView(in: current) {
                return mapView
            }
            candidate = current.superview
        }
        return nil
    }

    private static func searchMKMapView(in view: UIView) -> MKMapView? {
        if let mapView = view as? MKMapView {
            return mapView
        }
        for subview in view.subviews {
            if let mapView = searchMKMapView(in: subview) {
                return mapView
            }
        }
        return nil
    }
}

enum MapMetalLayerLocator {
    static func deepestViewWithMetalLayer(in view: UIView) -> UIView? {
        var bestMatch: UIView?

        if containsMetalLayer(in: view.layer) {
            bestMatch = view
        }

        for subview in view.subviews {
            if let deeper = deepestViewWithMetalLayer(in: subview) {
                bestMatch = deeper
            }
        }

        return bestMatch
    }

    private static func containsMetalLayer(in layer: CALayer) -> Bool {
        if layer is CAMetalLayer || layer.name == "MTKViewLayer" {
            return true
        }
        guard let sublayers = layer.sublayers else { return false }
        return sublayers.contains { containsMetalLayer(in: $0) }
    }
}

#endif
