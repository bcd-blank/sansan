//
//  HikingRecordListSupport.swift
//  sansan
//

#if os(iOS)

import SwiftUI

enum RecordsListChrome {
    static let accent = Color(red: 0.12, green: 0.72, blue: 0.45)
}

struct RecordDetailRoute: Identifiable, Hashable {
    let recordID: UUID

    var id: UUID { recordID }
}

enum RecordsListTab: String, CaseIterable, Identifiable {
    case saved
    case imported

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saved: "내 경로"
        case .imported: "불러온 경로"
        }
    }

    var icon: String {
        switch self {
        case .saved: "figure.hiking"
        case .imported: "tray.and.arrow.down"
        }
    }
}

#endif
