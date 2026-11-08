//
//  SupplementalAuthHandling.swift
//  Shared
//

#if os(iOS)

import Foundation

/// Apple 이외 로그인(Google 등) — iOS 앱 타겟에서 구현.
@MainActor
protocol SupplementalAuthHandling: AnyObject {
    var isGoogleSignInConfigured: Bool { get }

    func signInWithGoogle() async throws -> AuthUser
    func restoreGoogleSession(stored: AuthUser) async -> AuthUser?
    func signOutFromProvider(_ provider: AuthProvider)
}

#endif
