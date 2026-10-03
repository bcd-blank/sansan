//
//  AppDelegate.swift
//  sansan
//

#if os(iOS)

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if !AuthCapabilities.isSignInEnabled {
            UserDataPaths.activateLocalUser()
        }
        UIWindow.appearance().backgroundColor = .systemGroupedBackground
        configureNavigationBarAppearance()
        // 스플래시 이미지를 미리 로드해 SwiftUI 첫 프레임에서 검정 공백을 줄입니다.
        _ = UIImage(named: "LaunchScreenFull")
        return true
    }

    private func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemGroupedBackground
        appearance.shadowColor = .clear

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
    }
}

#endif


