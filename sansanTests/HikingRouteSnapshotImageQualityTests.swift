//
//  HikingRouteSnapshotImageQualityTests.swift
//  sansanTests
//

import UIKit
import XCTest
@testable import sansan

final class HikingRouteSnapshotImageQualityTests: XCTestCase {
    func testSolidBlackImageIsBlank() {
        let image = makeSolidImage(color: .black, size: CGSize(width: 48, height: 48))
        XCTAssertTrue(HikingRouteSnapshotImageQuality.isEffectivelyBlank(image))
    }

    func testSolidLightBackgroundImageIsBlank() {
        // Watch 동기화 직후 Metal 미렌더 시 drawHierarchy가 systemBackground만 남기는 경우.
        let image = makeSolidImage(
            color: UIColor.systemBackground,
            size: CGSize(width: 48, height: 48)
        )
        XCTAssertTrue(HikingRouteSnapshotImageQuality.isEffectivelyBlank(image))
    }

    func testContrastyRouteLikeImageIsNotBlank() {
        let size = CGSize(width: 48, height: 48)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(red: 0.85, green: 0.90, blue: 0.80, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.12, green: 0.72, blue: 0.45, alpha: 1).setStroke()
            let path = UIBezierPath()
            path.lineWidth = 4
            path.move(to: CGPoint(x: 6, y: 40))
            path.addLine(to: CGPoint(x: 22, y: 18))
            path.addLine(to: CGPoint(x: 42, y: 8))
            path.stroke()
        }
        XCTAssertFalse(HikingRouteSnapshotImageQuality.isEffectivelyBlank(image))
    }

    @MainActor
    func testNeedsListThumbnailWhenTooFewPoints() {
        let session = makeSession(pointCount: 1)
        let record = SavedHikingSession(session: session, endedAt: Date())
        XCTAssertFalse(HikingRecordStore.shared.needsListThumbnail(for: record))
    }

    @MainActor
    func testNeedsListThumbnailWhenPointsExistAndFileMissing() {
        let session = makeSession(pointCount: 3)
        let record = SavedHikingSession(session: session, endedAt: Date())
        // 파일이 없으면(또는 유저 루트 없음) 썸네일 생성이 필요합니다.
        XCTAssertTrue(HikingRecordStore.shared.needsListThumbnail(for: record))
    }

    private func makeSolidImage(color: UIColor, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeSession(pointCount: Int) -> HikingSessionData {
        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let points = (0..<pointCount).map { index in
            HikingPoint(
                latitude: 37.5 + Double(index) * 0.0001,
                longitude: 127.0 + Double(index) * 0.0001,
                altitude: 10,
                timestamp: base.addingTimeInterval(Double(index) * 3),
                horizontalAccuracy: 5
            )
        }
        var session = HikingSessionData(sessionID: sessionID, points: points, stepCount: nil)
        session.elapsedTime = Double(max(pointCount - 1, 0) * 3)
        session.totalDistance = Double(max(pointCount - 1, 0) * 10)
        return session
    }
}
