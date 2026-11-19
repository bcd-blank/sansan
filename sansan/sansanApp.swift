//
//  sansanApp.swift
//  sansan
//
//  Created by Park Jeongwook on 6/3/26.
//

import SwiftUI

#if os(iOS)
import UIKit

@main
struct sansanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var theme = AppThemePreferencesObserver.shared

    init() {
        UIWindow.appearance().backgroundColor = .systemGroupedBackground
        _ = UIImage(named: "LaunchScreenFull")
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .preferredColorScheme(forcedScreenshotColorScheme ?? theme.theme.colorScheme)
        }
    }

#if DEBUG
    /// 캡처용: `SANSAN_FORCE_COLOR_SCHEME=dark|light` (Info.plist Light여도 시뮬 다크 검수 가능).
    private var forcedScreenshotColorScheme: ColorScheme? {
        switch ProcessInfo.processInfo.environment["SANSAN_FORCE_COLOR_SCHEME"]?.lowercased() {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }
#else
    private var forcedScreenshotColorScheme: ColorScheme? { nil }
#endif
}
#endif
