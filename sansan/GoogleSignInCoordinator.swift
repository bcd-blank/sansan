//
//  GoogleSignInCoordinator.swift
//  sansan
//
//  GoogleSignIn SDK는 현재 미사용(SANSANEnableSignIn=false). 나중에 다시 켤 때 SPM을 추가합니다.
//

#if os(iOS)

import UIKit

@MainActor
final class GoogleSignInCoordinator: SupplementalAuthHandling {
    static let shared = GoogleSignInCoordinator()

    private init() {}

    var isGoogleSignInConfigured: Bool { false }

    func configure() {}

    func signInWithGoogle() async throws -> AuthUser {
        throw GoogleSignInCoordinatorError.notConfigured
    }

    func restoreGoogleSession(stored: AuthUser) async -> AuthUser? { nil }

    func signOutFromProvider(_ provider: AuthProvider) {}
}

enum GoogleSignInCoordinatorError: LocalizedError {
    case notConfigured
    case noPresenter
    case missingProfile

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Google 로그인은 현재 빌드에서 사용할 수 없습니다."
        case .noPresenter:
            "로그인 화면을 표시할 수 없습니다."
        case .missingProfile:
            "Google 계정 정보를 가져오지 못했습니다."
        }
    }
}

#endif
