//
//  AppStoreScreenshotMode.swift
//  sansan
//
//  DEBUG 전용 — 시뮬레이터 스크린샷 캡처용 (SANSAN_SCREENSHOT 환경 변수).
//

#if os(iOS) && DEBUG

import CoreLocation
import Foundation
import MapKit

enum AppStoreScreenshotMode: String {
    case dashboard
    /// Dashboard + 일반설정 sheet scrolled to image-save-style pager.
    case settings
    /// Dashboard + 일반설정 sheet at scroll Y=0 (size-parity titlebaseline top).
    case settingsTop = "settings-top"
    /// Dashboard + 일반설정 sheet scrolled to 「저장 · 공유 지도」 (photo toggles hidden).
    case settingsShareMap = "settings-share-map"
    case records
    case imported
    case kmsc
    case kmscDetail = "kmsc-detail"
    /// Alias for settings scroll-to-image-save (PR #18 capture helper).
    case imageSave = "image-save"
    /// Opens 모음 → A001 Seoul seed detail (size-parity / -UITestSeedRecords).
    case detail
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
        case .dashboard, .settings, .settingsTop, .settingsShareMap, .imageSave: false
        case .records, .imported, .kmsc, .kmscDetail, .detail, .detailZoom,
             .detailSaryang, .detailGahyeon, .detailSamak, .detailGamaji: true
        }
    }

    var opensGeneralSettings: Bool {
        self == .settings || self == .settingsTop || self == .settingsShareMap || self == .imageSave
    }

    /// Scroll so 「이미지 저장 방식」 sits under nav (Android gallery-at-top SoT).
    var scrollsToImageSaveStyle: Bool { self == .settings || self == .imageSave }

    /// Leave settings at scroll Y=0 (do not auto-scroll).
    var keepsSettingsScrollAtTop: Bool { self == .settingsTop }

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
        case .detail:
            return UUID(uuidString: "00000000-0000-4000-8000-00000000a001")
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
        /// 가마지천 SoT crops — fixed camera so Android can match the same point.
        case zoomRouteStraight
        case zoomRouteCurve
        case zoomRouteCross
    }

    static let fitName = "com.jw.sansan.uitest.mapFit" as CFString
    static let zoomInName = "com.jw.sansan.uitest.mapZoomIn" as CFString
    static let zoomStraightName = "com.jw.sansan.uitest.mapZoomRouteStraight" as CFString
    static let zoomCurveName = "com.jw.sansan.uitest.mapZoomRouteCurve" as CFString
    static let zoomCrossName = "com.jw.sansan.uitest.mapZoomRouteCross" as CFString

    /// 가마지천 a415 — dens-norm crop cameras (RESULT-route-casing / route-crossing).
    enum GamajiRouteCasingPose {
        static let span = MKCoordinateSpan(latitudeDelta: 0.00115, longitudeDelta: 0.00115)
        /// JW crossing SoT: 4× tighter than casing crop span (0.00115/4).
        static let cross4xSpan = MKCoordinateSpan(latitudeDelta: 0.0002875, longitudeDelta: 0.0002875)
        /// Long near-colinear stretch center (fixture idx ~207).
        static let straight = CLLocationCoordinate2D(latitude: 37.64311855, longitude: 126.63755373)
        /// Sharpest turn ~86.6° (fixture idx 285).
        static let curve = CLLocationCoordinate2D(latitude: 37.64010938, longitude: 126.64202434)
        /// True self-cross (edges 59×139, loop ~617m) — pond junction center.
        static let cross = CLLocationCoordinate2D(latitude: 37.64648737, longitude: 126.63456760)
    }

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
        CFNotificationCenterAddObserver(
            center, nil, uiTestMapZoomStraightNotify, zoomStraightName, nil, .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            center, nil, uiTestMapZoomCurveNotify, zoomCurveName, nil, .deliverImmediately
        )
        CFNotificationCenterAddObserver(
            center, nil, uiTestMapZoomCrossNotify, zoomCrossName, nil, .deliverImmediately
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

private let uiTestMapZoomStraightNotify: CFNotificationCallback = { _, _, _, _, _ in
    uiTestMapPostAction("zoomRouteStraight")
}

private let uiTestMapZoomCurveNotify: CFNotificationCallback = { _, _, _, _, _ in
    uiTestMapPostAction("zoomRouteCurve")
}

private let uiTestMapZoomCrossNotify: CFNotificationCallback = { _, _, _, _, _ in
    uiTestMapPostAction("zoomRouteCross")
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

