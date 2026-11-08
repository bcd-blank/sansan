//
//  FlythroughCapabilities.swift
//  sansan
//
//  3D 경로 영상(Flythrough) 모듈 공개 게이트.
//  구현은 `sansan/Flythrough/` 에 두고, 앱 진입점은 이 플래그만 확인합니다.
//

#if os(iOS)

import Foundation

enum FlythroughCapabilities {
    /// 3D 경로 영상 모듈 활성 여부.
    /// `Info.plist` 의 `SANSANEnableFlythrough` — 키가 없거나 false면 비활성(현재 기본값).
    /// 다시 켤 때 Info.plist에 `<key>SANSANEnableFlythrough</key><true/>` 를 추가하면 됩니다.
    static var isFeatureEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "SANSANEnableFlythrough") as? NSNumber)?.boolValue == true
    }
}

#endif
