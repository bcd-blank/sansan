//
//  AppStoreScreenshotMode.swift
//  sansan
//
//  DEBUG 전용 — 시뮬레이터 스크린샷 캡처용 (SANSAN_SCREENSHOT 환경 변수).
//

#if os(iOS) && DEBUG

import Foundation

enum AppStoreScreenshotMode: String {
    case dashboard
    case records
    case imported
    case kmsc
    case kmscDetail = "kmsc-detail"

    static var current: AppStoreScreenshotMode? {
        ProcessInfo.processInfo.environment["SANSAN_SCREENSHOT"].flatMap(AppStoreScreenshotMode.init(rawValue:))
    }

    var opensRecordsTab: Bool {
        switch self {
        case .dashboard: false
        case .records, .imported, .kmsc, .kmscDetail: true
        }
    }

    var recordsListTab: RecordsListTab? {
        switch self {
        case .imported: .imported
        default: nil
        }
    }

    var showsKMSCBrowser: Bool {
        switch self {
        case .kmsc, .kmscDetail: true
        default: false
        }
    }

    var opensKMSCCourseDetail: Bool {
        self == .kmscDetail
    }
}

#endif
