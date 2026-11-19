//
//  AppExportAppearance.swift
//  Shared
//
//  저장·공유 이미지 렌더 시 일반설정「테마」와 동일한 라이트/다크/시스템을 적용합니다.
//

#if os(iOS)

import MapKit
import SwiftUI
import UIKit

enum AppExportAppearance {
    nonisolated static let themeBaseKey = "sansan.appTheme"

    nonisolated static func storageKey() -> String {
        guard let userID = UserDataPaths.currentUserID else { return themeBaseKey }
        return "\(themeBaseKey).\(userID)"
    }

    nonisolated static func storedThemeRawValue() -> String {
        UserDefaults.standard.string(forKey: storageKey()) ?? "system"
    }

    @MainActor
    static func resolvedUserInterfaceStyle(in window: UIWindow? = nil) -> UIUserInterfaceStyle {
        switch storedThemeRawValue() {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            if let window {
                return window.traitCollection.userInterfaceStyle
            }
            return UITraitCollection.current.userInterfaceStyle
        }
    }

    @MainActor
    static func resolvedColorScheme(in window: UIWindow? = nil) -> ColorScheme {
        resolvedUserInterfaceStyle(in: window) == .dark ? .dark : .light
    }

    @MainActor
    static func apply(to viewController: UIViewController, in window: UIWindow? = nil) {
        let resolvedWindow = window ?? viewController.view.window
        viewController.overrideUserInterfaceStyle = resolvedUserInterfaceStyle(in: resolvedWindow)
    }

    @MainActor
    static func apply(to mapView: MKMapView, in window: UIWindow? = nil) {
        mapView.overrideUserInterfaceStyle = resolvedUserInterfaceStyle(in: window ?? mapView.window)
    }
}

#endif
