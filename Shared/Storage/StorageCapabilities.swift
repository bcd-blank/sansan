//
//  StorageCapabilities.swift
//  Shared
//

#if os(iOS)

import Foundation

enum StorageCapabilities {
    /// `Info.plist` 의 `SANSANEnableICloudSync`.
    /// iCloud entitlement·유료 개발자 계정이 준비된 경우에만 true 로 유지합니다.
    static var isICloudSyncEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "SANSANEnableICloudSync") as? NSNumber)?.boolValue == true
    }
}

#endif
