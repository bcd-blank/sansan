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
    /// Dashboard + 일반설정 sheet scrolled to image-save-style pager.
    case settings
    /// Dashboard + 일반설정 sheet scrolled to 「저장 · 공유 지도」 (photo toggles hidden).
    case settingsShareMap = "settings-share-map"
    case records
    case imported
    case kmsc
    case kmscDetail = "kmsc-detail"
    /// Opens 모음 → short seeded 4.28km detail for km-label zoom captures.
    case detailZoom = "detail-zoom"
    case detailSaryang = "detail-saryang"
    case detailGahyeon = "detail-gahyeon"
    case detailSamak = "detail-samak"
    /// 가마지천 상세 — 교차 overlay 캡처.
    case detailGamaji = "detail-gamaji"

    static var current: AppStoreScreenshotMode? {
        // Prefer launch args — SIMCTL_CHILD_* env can stick to a stale value on some runtimes.
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-SANSAN_SCREENSHOT"),
           args.index(after: idx) < args.endIndex,
           let mode = AppStoreScreenshotMode(rawValue: args[args.index(after: idx)]) {
            return mode
        }
        if let env = ProcessInfo.processInfo.environment["SANSAN_SCREENSHOT"],
           let mode = AppStoreScreenshotMode(rawValue: env) {
            return mode
        }
        return nil
    }

    var opensRecordsTab: Bool {
        switch self {
        case .dashboard, .settings, .settingsShareMap: false
        case .records, .imported, .kmsc, .kmscDetail, .detailZoom,
             .detailSaryang, .detailGahyeon, .detailSamak, .detailGamaji: true
        }
    }

    var opensGeneralSettings: Bool {
        self == .settings || self == .settingsShareMap
    }

    var scrollsToImageSaveStyle: Bool { self == .settings }

    var scrollsToShareMapExport: Bool { self == .settingsShareMap }

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

    var opensShortDetailRecord: Bool {
        self == .detailZoom || self == .detailGahyeon
    }

    /// Seeded record UUID to open for label-placement captures (nil = no auto-open).
    var opensSeededDetailRecordID: UUID? {
        switch self {
        case .detailZoom, .detailGahyeon:
            return UUID(uuidString: "00000000-0000-4000-8000-00000000a428")
        case .detailSaryang:
            return UUID(uuidString: "00000000-0000-4000-8000-00000000a820")
        case .detailSamak:
            return UUID(uuidString: "00000000-0000-4000-8000-00000000a610")
        case .detailGamaji:
            return UUID(uuidString: "00000000-0000-4000-8000-00000000a415")
        default:
            return nil
        }
    }
}

/// Darwin notify hooks for simulator km-label zoom captures (`simctl spawn … notifyutil -p`).
enum UITestMapCaptureHooks {
    enum Action {
        case fit
        case zoomIn
    }

    static let fitName = "com.jw.sansan.uitest.mapFit" as CFString
    static let zoomInName = "com.jw.sansan.uitest.mapZoomIn" as CFString

    private static var installed = false

    static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center, nil, uiTestMapFitNotify, fitName, nil, .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            center, nil, uiTestMapZoomInNotify, zoomInName, nil, .deliverImmediately
        )
        UITestSaveStyleCaptureHooks.installIfNeeded()
    }
}

/// Darwin notify → image-save-style pager page (`saveStylePage0`…`2`)
/// and saved selection (`saveStyleSelect0`…`2`) for selected/unselected captures.
enum UITestSaveStyleCaptureHooks {
    static let page0Name = "com.jw.sansan.uitest.saveStylePage0" as CFString
    static let page1Name = "com.jw.sansan.uitest.saveStylePage1" as CFString
    static let page2Name = "com.jw.sansan.uitest.saveStylePage2" as CFString
    static let select0Name = "com.jw.sansan.uitest.saveStyleSelect0" as CFString
    static let select1Name = "com.jw.sansan.uitest.saveStyleSelect1" as CFString
    static let select2Name = "com.jw.sansan.uitest.saveStyleSelect2" as CFString

    private static var installed = false

    static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center, nil, uiTestSaveStylePage0Notify, page0Name, nil, .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            center, nil, uiTestSaveStylePage1Notify, page1Name, nil, .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            center, nil, uiTestSaveStylePage2Notify, page2Name, nil, .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            center, nil, uiTestSaveStyleSelect0Notify, select0Name, nil, .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            center, nil, uiTestSaveStyleSelect1Notify, select1Name, nil, .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            center, nil, uiTestSaveStyleSelect2Notify, select2Name, nil, .deliverImmediately
        )
    }
}

private func uiTestMapPostAction(_ key: String) {
    DispatchQueue.main.async {
        NotificationCenter.default.post(
            name: .uiTestMapCaptureAction,
            object: nil,
            userInfo: ["action": key]
        )
    }
}

private let uiTestMapFitNotify: CFNotificationCallback = { _, _, _, _, _ in
    uiTestMapPostAction("fit")
}

private let uiTestMapZoomInNotify: CFNotificationCallback = { _, _, _, _, _ in
    uiTestMapPostAction("zoomIn")
}

private func uiTestSaveStylePostPage(_ index: Int) {
    DispatchQueue.main.async {
        NotificationCenter.default.post(
            name: .uiTestSaveStylePage,
            object: nil,
            userInfo: ["index": index]
        )
    }
}

private func uiTestSaveStylePostSelect(_ index: Int) {
    DispatchQueue.main.async {
        NotificationCenter.default.post(
            name: .uiTestSaveStyleSelect,
            object: nil,
            userInfo: ["index": index]
        )
    }
}

private let uiTestSaveStylePage0Notify: CFNotificationCallback = { _, _, _, _, _ in
    uiTestSaveStylePostPage(0)
}

private let uiTestSaveStylePage1Notify: CFNotificationCallback = { _, _, _, _, _ in
    uiTestSaveStylePostPage(1)
}

private let uiTestSaveStylePage2Notify: CFNotificationCallback = { _, _, _, _, _ in
    uiTestSaveStylePostPage(2)
}

private let uiTestSaveStyleSelect0Notify: CFNotificationCallback = { _, _, _, _, _ in
    uiTestSaveStylePostSelect(0)
}

private let uiTestSaveStyleSelect1Notify: CFNotificationCallback = { _, _, _, _, _ in
    uiTestSaveStylePostSelect(1)
}

private let uiTestSaveStyleSelect2Notify: CFNotificationCallback = { _, _, _, _, _ in
    uiTestSaveStylePostSelect(2)
}

extension Notification.Name {
    static let uiTestMapCaptureAction = Notification.Name("sansan.uiTestMapCaptureAction")
    static let uiTestSaveStylePage = Notification.Name("sansan.uiTestSaveStylePage")
    static let uiTestSaveStyleSelect = Notification.Name("sansan.uiTestSaveStyleSelect")
}

#endif

