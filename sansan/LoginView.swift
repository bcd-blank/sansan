//
//  LoginView.swift
//  sansan
//

#if os(iOS)

import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @ObservedObject private var auth = AuthManager.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .blue.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text("sansan")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text("나만의 등산 기록을 안전하게 저장하세요")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 14) {
                if auth.isGoogleSignInAvailable {
                    Button {
                        auth.signInWithGoogle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "g.circle.fill")
                                .font(.body.weight(.semibold))
                            Text("Google로 계속하기")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(auth.isLoading)
                }

                if auth.isAppleSignInAvailable {
                    Button {
                        auth.signInWithApple()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "applelogo")
                                .font(.body.weight(.semibold))
                            Text("Apple로 계속하기")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.bordered)
                    .tint(.primary)
                    .disabled(auth.isLoading)
                }

                if auth.isLoading {
                    ProgressView()
                }

                if let errorMessage = auth.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Text(loginFooterMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private var loginFooterMessage: String {
        switch (auth.isGoogleSignInAvailable, auth.isAppleSignInAvailable) {
        case (true, true):
            "Apple 또는 Google 계정으로 로그인하면 이 기기에 등산 기록이 개인별로 저장됩니다."
        case (true, false):
            "Google 계정으로 로그인하면 이 기기에 등산 기록이 개인별로 저장됩니다."
        case (false, true):
            "Apple 계정으로 로그인하면 이 기기에 등산 기록이 개인별로 저장됩니다."
        case (false, false):
            "GoogleService-Info.plist를 설정하면 Google 로그인을 사용할 수 있습니다."
        }
    }
}

#Preview {
    LoginView()
}

#endif
