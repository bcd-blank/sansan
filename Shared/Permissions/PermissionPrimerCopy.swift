//
//  PermissionPrimerCopy.swift
//  Shared
//
//  시스템 권한 요청 전 안내 문구.
//

import Foundation

enum PermissionPrimerCopy {
    // MARK: - 위치 (필수)

    static let locationTitle = "위치 접근"

    static let locationMessage =
        "등산 경로를 기록하려면 위치 정보가 필요합니다.\n\n허용하지 않으면 기록이 되지 않습니다."

    static let locationDeniedTitle = "위치 권한이 필요합니다"

    static let locationDeniedMessage =
        "설정에서 sansan의 위치 접근을 허용해 주세요.\n\n허용하지 않으면 기록이 되지 않습니다."

#if os(watchOS)
    static let locationDeniedWatchMessage =
        "설정 → 개인정보 보호 → 위치 서비스에서 sansan의 위치 접근을 허용해 주세요.\n\n허용하지 않으면 기록이 되지 않습니다."
#endif

    static let allowButtonTitle = "허용하기"
    static let openSettingsButtonTitle = "설정 열기"

#if os(iOS)
    // MARK: - 위치 항상 허용 (권장)

    static let locationAlwaysTitle = "백그라운드 위치"

    static let locationAlwaysMessage =
        "화면을 끄거나 잠금 상태에서도 경로를 이어 기록하려면「항상」허용이 필요합니다.\n\n거부해도 앱을 켠 동안에는 기록됩니다."

    // MARK: - 심박수 (선택)

    static let heartRateTitle = "건강 데이터 접근"

    static let heartRateMessage =
        "심박수를 표시하려면 건강 앱의 심박 데이터 읽기 권한이 필요합니다.\n\n허용하지 않아도 등산 기록은 가능합니다."
#endif
}
