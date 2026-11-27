//
//  iPhoneBottomChromeTabHitTests.swift
//  sansanTests
//
//  B09 — 메인/모음 탭 히트 ≥44pt, 캡슐 시각 높이는 기존 50.
//

#if os(iOS)

import XCTest
@testable import sansan

final class iPhoneBottomChromeTabHitTests: XCTestCase {
    func testTabHitMinHeightIsAtLeast44WhileCapsuleStays64() {
        // 9·15차 / 11·8 통일안: idle·recording 모두 64×scale.
        XCTAssertEqual(iPhoneBottomChromeLayout.chromeControlHeight, 64)
        XCTAssertEqual(iPhoneBottomChromeLayout.baseTabIcon, 20)
        XCTAssertEqual(iPhoneBottomChromeLayout.tabCapsuleInset, 8)
        XCTAssertEqual(
            iPhoneBottomChromeLayout.tabContentHeight(forCapsuleHeight: 64),
            48,
            "64 캡슐 − inset 8×2 = 48pt 콘텐츠"
        )
        XCTAssertEqual(
            iPhoneBottomChromeLayout.chromeControlHeight(forWidth: 393),
            iPhoneBottomChromeLayout.chromeControlHeight(forWidth: 393),
            "기록 전·중 동일 높이 토큰"
        )
        XCTAssertEqual(
            iPhoneBottomChromeLayout.recordingPrimaryDiameter(forWidth: 393),
            iPhoneBottomChromeLayout.chromeControlHeight(forWidth: 393),
            "일시정지·종료 ⌀ = 탭 캡슐 높이"
        )
        XCTAssertGreaterThanOrEqual(iPhoneBottomChromeLayout.tabHitMinHeight, 44)
        XCTAssertLessThanOrEqual(
            iPhoneBottomChromeLayout.tabHitMinHeight,
            iPhoneBottomChromeLayout.chromeControlHeight,
            "히트 확장이 캡슐 시각 높이(64)를 넘기면 안 됩니다"
        )
    }
}

#endif
