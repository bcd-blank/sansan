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
    case settings
    case detail
    /// 일반설정 → 「이미지 저장 방식」 섹션(다크 대비 점검).
    case imageSave = "image-save"

    static var current: AppStoreScreenshotMode? {
        ProcessInfo.processInfo.environment["SANSAN_SCREENSHOT"].flatMap(AppStoreScreenshotMode.init(rawValue:))
    }

    var opensRecordsTab: Bool {
        switch self {
        case .dashboard, .settings, .imageSave: false
        case .records, .imported, .kmsc, .kmscDetail, .detail: true
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

    var opensGeneralSettings: Bool {
        self == .settings || self == .imageSave
    }

    var opensFirstRecordDetail: Bool {
        self == .detail
    }

    var scrollsToImageSaveStyle: Bool {
        self == .imageSave
    }
}

#endif
