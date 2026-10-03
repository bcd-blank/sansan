//
//  AppleMapsAttributionImage.swift
//  Shared
//
//  MKMapView가 그리는 Apple Maps 법적 표기를 래스터화해 카드 고정 레이어로 씁니다.
//

#if os(iOS)

import MapKit
import UIKit

@MainActor
enum AppleMapsAttributionImage {
    private static var cache: [String: UIImage] = [:]

    /// `referenceWidth`에 맞춘 법적 표기 배지(지도 캡처와 무관하게 카드 좌하단에 고정).
    static func raster(referenceWidth: CGFloat, scale: CGFloat = 2) -> UIImage? {
        let style = AppExportAppearance.resolvedUserInterfaceStyle()
        let key = "\(Int(referenceWidth * 10))-\(Int(scale * 10))-\(style.rawValue)"
        if let cached = cache[key] { return cached }

        guard referenceWidth > 0, let image = capture(referenceWidth: referenceWidth, scale: scale) else {
            return nil
        }
        cache[key] = image
        return image
    }

    private static func capture(referenceWidth: CGFloat, scale: CGFloat) -> UIImage? {
        guard let windowScene = activeWindowScene else { return nil }

        let stripHeight = RouteMapOverlayMetrics.legalAttributionStripHeight(forCanvasWidth: referenceWidth)
        let stripWidth = RouteMapOverlayMetrics.scaled(
            RouteMapOverlayMetrics.legalAttributionWidth,
            forCanvasWidth: referenceWidth
        )
        let mapHeight = max(stripHeight * 2.4, 72)
        let mapSize = CGSize(width: referenceWidth, height: mapHeight)

        let origin = CGPoint(x: -referenceWidth - 48, y: -mapHeight - 48)
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(origin: origin, size: mapSize)
        window.windowLevel = .normal
        window.isUserInteractionEnabled = false
        window.clipsToBounds = true
        window.isHidden = false

        let root = UIViewController()
        root.view.frame = CGRect(origin: .zero, size: mapSize)
        window.rootViewController = root

        let mapView = MKMapView(frame: root.view.bounds)
        mapView.preferredConfiguration = MKStandardMapConfiguration(
            elevationStyle: .flat,
            emphasisStyle: .default
        )
        AppExportAppearance.apply(to: mapView, in: window)
        mapView.isScrollEnabled = false
        mapView.isZoomEnabled = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        root.view.addSubview(mapView)
        root.view.layoutIfNeeded()
        mapView.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: mapSize, format: format)
        let snapshot = renderer.image { _ in
            mapView.drawHierarchy(in: mapView.bounds, afterScreenUpdates: true)
        }

        window.isHidden = true
        window.rootViewController = nil

        let cropRect = CGRect(
            x: 0,
            y: mapHeight - stripHeight,
            width: min(stripWidth, referenceWidth),
            height: stripHeight
        )
        guard let cgImage = snapshot.cgImage?.cropping(to: cropRect.scaled(for: snapshot.scale)) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }

    private static var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}

private extension CGRect {
    func scaled(for imageScale: CGFloat) -> CGRect {
        CGRect(
            x: origin.x * imageScale,
            y: origin.y * imageScale,
            width: size.width * imageScale,
            height: size.height * imageScale
        )
    }
}

#endif
