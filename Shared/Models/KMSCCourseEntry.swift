//
//  KMSCCourseEntry.swift
//  Shared
//
//  KMSC 공공 코스 한 건. 목록은 번들 JSON, GPX는 필요할 때 내려받습니다.
//

import Foundation

nonisolated struct KMSCCourseEntry: Identifiable, Hashable, Sendable, Codable {
    /// KMSC 기준 상대 경로 (예: `100대명산/월악산/월악산_0000000001.gpx`).
    let id: String
    /// 최상위 카테고리 (예: `100대명산`).
    let category: String
    /// 카테고리 아래 묶음 (예: `월악산`, `한남정맥`).
    let groupName: String
    /// 목록·상세 표시 이름.
    let title: String
    /// 호스팅 루트 기준 상대 경로 (`id`와 동일).
    let relativePath: String

    var subtitle: String {
        "\(category) · \(groupName)"
    }
}
