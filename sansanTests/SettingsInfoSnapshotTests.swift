//
//  SettingsInfoSnapshotTests.swift
//  sansanTests
//
//  일반설정 「정보」 4상태를 PNG로 저장합니다.
//

#if os(iOS)

import SwiftUI
import UIKit
import XCTest
@testable import sansan

@MainActor
final class SettingsInfoSnapshotTests: XCTestCase {
    func testCaptureInfoSectionFourStates() throws {
        let outDir = URL(fileURLWithPath: "/tmp/settings-info-ios-capture", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let cases: [(String, AppUpdateStatus)] = [
            ("01-checking", .checking),
            ("02-up-to-date", .upToDate),
            (
                "03-available",
                .available(
                    version: "1.0.7",
                    url: URL(string: "https://apps.apple.com/kr/app/id6800198509")!
                )
            ),
            ("04-failed", .failed),
        ]

        for (name, status) in cases {
            let root = NavigationStack {
                Form {
                    SettingsInfoSection(
                        status: status,
                        versionLabel: "1.0.6 (23)",
                        marketingVersion: "1.0.6",
                        buildVersion: "23",
                        onOpenStore: { _ in },
                        onRetry: {}
                    )
                }
                .navigationTitle("일반설정")
                .navigationBarTitleDisplayMode(.inline)
            }
            let host = UIHostingController(rootView: root)
            host.overrideUserInterfaceStyle = .light

            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()

            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            host.view.layoutIfNeeded()

            let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
            let image = renderer.image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            guard let png = image.pngData() else {
                XCTFail("Failed to encode \(name) PNG")
                return
            }

            let url = outDir.appendingPathComponent("settings-info-\(name).png")
            try png.write(to: url)
            print("SETTINGS_INFO_SNAPSHOT: \(url.path)")

            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)

            XCTAssertGreaterThan(png.count, 5_000, name)
        }

        // Distinct states must not produce byte-identical images.
        let checking = try Data(contentsOf: outDir.appendingPathComponent("settings-info-01-checking.png"))
        let upToDate = try Data(contentsOf: outDir.appendingPathComponent("settings-info-02-up-to-date.png"))
        let available = try Data(contentsOf: outDir.appendingPathComponent("settings-info-03-available.png"))
        let failed = try Data(contentsOf: outDir.appendingPathComponent("settings-info-04-failed.png"))
        XCTAssertNotEqual(checking, upToDate)
        XCTAssertNotEqual(upToDate, available)
        XCTAssertNotEqual(available, failed)
        XCTAssertNotEqual(checking, failed)
    }
}

#endif
