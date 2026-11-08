//
//  UserAccountStore.swift
//  Shared
//

import Foundation

enum UserAccountStore {
    private static let service = "com.jw.sansan.auth"
    private static let account = "currentUser"

    static func loadUser() -> AuthUser? {
        guard let data = KeychainStorage.load(service: service, account: account) else { return nil }
        return try? JSONDecoder().decode(AuthUser.self, from: data)
    }

    static func saveUser(_ user: AuthUser) throws {
        let data = try JSONEncoder().encode(user)
        try KeychainStorage.save(data, service: service, account: account)
    }

    static func clearUser() throws {
        try KeychainStorage.delete(service: service, account: account)
    }
}
