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
                .preferredColorScheme(theme.theme.colorScheme)
        }
    }
}
#endif
