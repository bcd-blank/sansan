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
    /// Opens 모음 → short seeded 4.28km detail for km-label zoom captures.
    case detailZoom = "detail-zoom"
    case detailSaryang = "detail-saryang"
    case detailGahyeon = "detail-gahyeon"
    case detailSamak = "detail-samak"

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
        case .dashboard: false
        case .records, .imported, .kmsc, .kmscDetail, .detailZoom,
             .detailSaryang, .detailGahyeon, .detailSamak: true
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

extension Notification.Name {
    static let uiTestMapCaptureAction = Notification.Name("sansan.uiTestMapCaptureAction")
}

#endif
