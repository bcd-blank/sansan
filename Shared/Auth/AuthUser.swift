//
//  AuthUser.swift
//  Shared
//

import Foundation

/// 로그인한 사용자(Apple / Google 식별자).
struct AuthUser: Codable, Equatable, Sendable {
    let provider: AuthProvider
    let id: String
    var displayName: String?

    init(provider: AuthProvider, id: String, displayName: String?) {
        self.provider = provider
        self.id = id
        self.displayName = displayName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        provider = try container.decodeIfPresent(AuthProvider.self, forKey: .provider) ?? .apple
    }

    /// Documents/users/ 하위 폴더 이름 (기존 Apple 사용자 경로 유지).
    var storageUserID: String {
        switch provider {
        case .apple:
            id
        case .google:
            "google_\(id)"
        }
    }

    var providerLabel: String {
        switch provider {
        case .apple: "Apple"
        case .google: "Google"
        }
    }

    var shortDisplayName: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return "등산 기록"
    }
}
