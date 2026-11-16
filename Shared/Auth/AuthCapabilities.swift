//
//  AuthCapabilities.swift
//  Shared
//

#if os(iOS)

import Foundation

enum AuthCapabilities {
    /// `Info.plist` 의 `SANSANEnableSignIn`. false 이면 로그인 없이 기기 로컬 저장만 사용.
    static var isSignInEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "SANSANEnableSignIn") as? NSNumber)?.boolValue == true
    }

    /// `Info.plist` 의 `SANSANEnableAppleSignIn`. 개인 무료 개발 팀은 Apple 로그인 entitlement 미지원.
    static var isAppleSignInEnabled: Bool {
        isSignInEnabled
            && (Bundle.main.object(forInfoDictionaryKey: "SANSANEnableAppleSignIn") as? NSNumber)?.boolValue == true
    }
}

#endif
