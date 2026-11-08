//
//  KmVoiceGuidanceSettingsSnapshotTests.swift
//  sansanTests
//
//  일반설정 「1km 음성 안내」 화면을 호스팅해 PNG로 저장합니다.
//

#if os(iOS)

import SwiftUI
import UIKit
import XCTest
@testable import sansan

@MainActor
final class KmVoiceGuidanceSettingsSnapshotTests: XCTestCase {
    func testCaptureGeneralSettingsWithKmVoiceToggle() throws {
        KmVoiceGuidancePreferences.isEnabled = true

        let root = NavigationStack {
            GeneralSettingsView()
        }
        let host = UIHostingController(rootView: root)
        host.overrideUserInterfaceStyle = .light

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()

        // Allow Form layout + preference sync.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.view.layoutIfNeeded()

        // 「1km 음성 안내」가 보이도록 스크롤합니다.
        if let scrollView = firstScrollView(in: host.view) {
            let targetY = min(
                max(0, scrollView.contentSize.height - scrollView.bounds.height),
                420
            )
            scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: false)
            host.view.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
        let image = renderer.image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        guard let png = image.pngData() else {
            XCTFail("Failed to encode settings snapshot PNG")
            return
        }

        let outDirs = [
            URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("km-voice-ios", isDirectory: true),
            URL(fileURLWithPath: "/tmp/km-voice-ios-capture", isDirectory: true),
        ]
        for dir in outDirs {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("settings-km-voice-light.png")
            try png.write(to: url)
            print("KM_VOICE_SNAPSHOT: \(url.path)")
        }

        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "settings-km-voice-light"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertGreaterThan(png.count, 10_000)
    }

    private func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for child in view.subviews {
            if let found = firstScrollView(in: child) { return found }
        }
        return nil
    }
}

#endif

