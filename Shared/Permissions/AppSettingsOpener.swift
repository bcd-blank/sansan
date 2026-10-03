//
//  AppSettingsOpener.swift
//  Shared
//

import Foundation
#if os(iOS)
import UIKit
#endif

enum AppSettingsOpener {
    static func open() {
#if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
#endif
    }
}
