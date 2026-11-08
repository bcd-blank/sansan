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
    func testTabHitMinHeightIsAtLeast44WhileCapsuleStays50() {
        XCTAssertEqual(iPhoneBottomChromeLayout.chromeControlHeight, 50)
        XCTAssertEqual(iPhoneBottomChromeLayout.tabCapsuleInset, 8)
        XCTAssertEqual(
            iPhoneBottomChromeLayout.tabContentHeight(forCapsuleHeight: 50),
            34,
            "시각 콘텐츠 높이는 기존 34pt 유지"
        )
        XCTAssertGreaterThanOrEqual(iPhoneBottomChromeLayout.tabHitMinHeight, 44)
        XCTAssertLessThanOrEqual(
            iPhoneBottomChromeLayout.tabHitMinHeight,
            iPhoneBottomChromeLayout.chromeControlHeight,
            "히트 확장이 캡슐 시각 높이(50)를 넘기면 안 됩니다"
        )
    }
}

#endif
