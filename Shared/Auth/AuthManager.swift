//
//  AuthManager.swift
//  Shared
//

#if os(iOS)

import AuthenticationServices
import Combine
import Foundation
import UIKit

@MainActor
final class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var currentUser: AuthUser?
    @Published private(set) var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Google 로그인 — sansan 앱에서 `GoogleSignInCoordinator` 등록.
    weak var supplementalAuth: (any SupplementalAuthHandling)?

    var isAppleSignInAvailable: Bool {
        AuthCapabilities.isAppleSignInEnabled
    }

    var isGoogleSignInAvailable: Bool {
        AuthCapabilities.isSignInEnabled
            && supplementalAuth?.isGoogleSignInConfigured == true
    }

    private override init() {
        super.init()
    }

    func restoreSession() async {
        guard AuthCapabilities.isSignInEnabled else {
            deactivateDataSession()
            return
        }

        deactivateDataSession()

        guard let stored = UserAccountStore.loadUser() else {
            return
        }

        switch stored.provider {
        case .apple:
            guard isAppleSignInAvailable else {
                try? UserAccountStore.clearUser()
                deactivateDataSession()
                errorMessage = "Apple 로그인은 현재 빌드에서 사용할 수 없습니다. Google로 다시 로그인해 주세요."
                return
            }
            await restoreAppleSession(stored: stored)
        case .google:
            await restoreGoogleSession(stored: stored)
        }
    }

    func signInWithApple() {
        guard !isLoading else { return }
        guard isAppleSignInAvailable else {
            errorMessage = "Apple 로그인은 Apple Developer Program(유료) 가입 후 사용할 수 있습니다."
            return
        }
        errorMessage = nil
        isLoading = true

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func signInWithGoogle() {
        guard !isLoading else { return }
        guard let supplementalAuth, supplementalAuth.isGoogleSignInConfigured else {
            errorMessage = "Google 로그인을 사용하려면 GoogleService-Info.plist를 설정해 주세요."
            return
        }

        errorMessage = nil
        isLoading = true

        Task {
            do {
                let user = try await supplementalAuth.signInWithGoogle()
                completeSignIn(with: user)
            } catch {
                let nsError = error as NSError
                if nsError.domain == "com.google.GIDSignIn", nsError.code == -5 {
                    isLoading = false
                    return
                }
                if let message = (error as? LocalizedError)?.errorDescription {
                    failSignIn(message: message)
                } else {
                    failSignIn(message: "Google 로그인에 실패했습니다. 다시 시도해 주세요.")
                }
            }
        }
    }

    func signOut() {
        if WorkoutManager.shared.sessionData.state != .idle {
            WorkoutManager.shared.endWorkout()
        }
        if let user = currentUser {
            supplementalAuth?.signOutFromProvider(user.provider)
        }
        try? UserAccountStore.clearUser()
        currentUser = nil
        isAuthenticated = false
        errorMessage = nil
        deactivateDataSession()
    }

    private func restoreAppleSession(stored: AuthUser) async {
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: stored.id)
            switch state {
            case .authorized:
                currentUser = stored
                isAuthenticated = true
                activateDataSession(for: stored)
            case .revoked, .notFound, .transferred:
                try? UserAccountStore.clearUser()
                deactivateDataSession()
            @unknown default:
                deactivateDataSession()
            }
        } catch {
            deactivateDataSession()
        }
    }

    private func restoreGoogleSession(stored: AuthUser) async {
        guard let supplementalAuth,
              let user = await supplementalAuth.restoreGoogleSession(stored: stored) else {
            try? UserAccountStore.clearUser()
            deactivateDataSession()
            return
        }
        currentUser = user
        isAuthenticated = true
        activateDataSession(for: user)
    }

    private func completeSignIn(with user: AuthUser) {
        do {
            try UserAccountStore.saveUser(user)
            currentUser = user
            isAuthenticated = true
            activateDataSession(for: user)
        } catch {
            errorMessage = "계정 정보를 저장하지 못했습니다."
        }
        isLoading = false
    }

    private func failSignIn(message: String) {
        errorMessage = message
        isLoading = false
    }

    private func activateDataSession(for user: AuthUser) {
        UserDataPaths.setActiveUser(user.storageUserID)
        UserDataPaths.migrateLegacyDataIfNeeded(for: user.storageUserID)
        HikingRecordStore.shared.reloadForCurrentUser()
    }

    private func deactivateDataSession() {
        currentUser = nil
        isAuthenticated = false
        UserDataPaths.clearActiveUser()
        HikingRecordStore.shared.clearForSignOut()
    }

    private static func displayName(from credential: ASAuthorizationAppleIDCredential) -> String? {
        guard let components = credential.fullName else { return nil }
        let parts = [components.familyName, components.givenName].compactMap { $0 }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }
}

extension AuthManager: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                failSignIn(message: "Apple 로그인 정보를 읽을 수 없습니다.")
                return
            }

            let previous = UserAccountStore.loadUser()
            let name = Self.displayName(from: credential) ?? previous?.displayName
            let user = AuthUser(provider: .apple, id: credential.user, displayName: name)
            completeSignIn(with: user)
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               nsError.code == ASAuthorizationError.canceled.rawValue {
                isLoading = false
                return
            }
            failSignIn(message: "로그인에 실패했습니다. 다시 시도해 주세요.")
        }
    }
}

extension AuthManager: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { presentationAnchorOnMainActor() }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                presentationAnchorOnMainActor()
            }
        }
    }

    @MainActor
    private func presentationAnchorOnMainActor() -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? scenes.compactMap { $0 as? UIWindowScene }.first

        if let window = windowScene?.windows.first(where: \.isKeyWindow) {
            return window
        }
        guard let windowScene else {
            fatalError("No UIWindowScene available for Sign in with Apple presentation.")
        }
        return ASPresentationAnchor(windowScene: windowScene)
    }
}

#endif
