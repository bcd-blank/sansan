//
//  GoogleAuthSecrets.swift
//  sansan
//

#if os(iOS)

import Foundation

enum GoogleAuthSecrets {
    /// `sansan/GoogleService-Info.plist` 의 CLIENT_ID (Google Cloud Console iOS 클라이언트).
    static var clientID: String? {
        guard
            let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
            let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
            let clientID = dict["CLIENT_ID"] as? String,
            !clientID.isEmpty,
            !clientID.contains("YOUR_")
        else { return nil }
        return clientID
    }

    /// Info.plist URL Types 에 넣을 값 (`REVERSED_CLIENT_ID`).
    static var reversedClientID: String? {
        guard
            let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
            let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
            let value = dict["REVERSED_CLIENT_ID"] as? String,
            !value.isEmpty,
            !value.contains("YOUR_")
        else { return nil }
        return value
    }
}

#endif
