//
//  ChromeSizes.swift
//  Shared
//
//  Cross-platform chrome size tokens (iPhone SoT).
//  Mirror of docs/design-tokens/chrome-sizes.json (== Shared/Resources/chrome_sizes.json).
//  Values are design pt; Android mirrors 1:1 as dp at the same logical width.
//

import CoreGraphics
import Foundation

/// Shared chrome / card / bottom-bar sizes. Source of truth: iPhone.
enum ChromeSizes {
    static let id = "chrome.sizes"
    static let referenceLogicalWidth: CGFloat = 393

    // MARK: - Main

    enum Main {
        static let horizontalMargin: CGFloat = 16
        static let cardGap: CGFloat = 12
        static let cardInnerPadding: CGFloat = 11
        static let cardCornerRadius: CGFloat = 14
        static let sectionSpacing: CGFloat = 16

        enum MapCard {
            static let height: CGFloat = 320
            static let cornerRadius: CGFloat = 16
        }

        enum HeaderBand {
            static let avatar: CGFloat = 36
            static let brandTitleSize: CGFloat = 22
            static let weatherButton: CGFloat = 40
            static let paddingLeading: CGFloat = 16
            static let paddingTrailing: CGFloat = 10
            static let paddingVertical: CGFloat = 6
            static let rowSpacing: CGFloat = 10
        }
    }

    // MARK: - Data card (main + detail metrics)

    enum DataCard {
        static let minHeight: CGFloat = 78
        static let innerPadding: CGFloat = 11
        static let cornerRadius: CGFloat = 14
        static let rowSpacing: CGFloat = 6
        static let iconLabelGap: CGFloat = 5
        static let iconBox: CGFloat = 22
        static let iconSymbol: CGFloat = 11
        static let iconCornerRadius: CGFloat = 6
        static let valueUnitGap: CGFloat = 3

        enum Font {
            static let label: CGFloat = 10
            static let value: CGFloat = 22
            static let unit: CGFloat = 11
        }
    }

    // MARK: - Bottom chrome (main + detail + collection)

    enum BottomChrome {
        static let requiredWidth: CGFloat = 392.6666666667
        static let outerHeight: CGFloat = 64
        static let radius: CGFloat = 32
        static let sideInset: CGFloat = 20
        static let bottomInset: CGFloat = 26
        static let scrollEndBuffer: CGFloat = 16
        static let floatingHeight: CGFloat = outerHeight + bottomInset // 90
        static let tabItemMinWidth: CGFloat = 72
        static let tabCapsuleInset: CGFloat = 8
        static let selectionInset: CGFloat = 6
        static let circleGap: CGFloat = 4
        static let clusterGap: CGFloat = 8
        static let tabLabelMin: CGFloat = 10
        static let minTouchIOS: CGFloat = 44
        static let minTouchAndroid: CGFloat = 48
        static let collectionListScrollExtra: CGFloat = 4

        enum StartButton {
            static let width: CGFloat = 127
            static let height: CGFloat = 64
            static let labelSize: CGFloat = 15
        }
    }

    // MARK: - Detail

    enum Detail {
        static let horizontalPadding: CGFloat = 8
        static let contentWidthInset: CGFloat = 16
        static let topPadding: CGFloat = 6
        static let bottomPadding: CGFloat = 10
        static let sectionSpacing: CGFloat = 10
        static let cardGridSpacing: CGFloat = 8
        static let referenceContentWidth: CGFloat = 377
        static let referenceViewportHeight: CGFloat = 780

        enum TopButtons {
            static let minTouch: CGFloat = 44
            /// Visible liquid-glass circle (matches minTouch on iPhone toolbar).
            static let visibleDiameter: CGFloat = 44
        }

        enum TitleCard {
            static let cornerRadius: CGFloat = 14
            static let innerPadding: CGFloat = 11
            static let iconBox: CGFloat = 28
            static let iconSymbol: CGFloat = 13
            static let iconSpacing: CGFloat = 10
            static let titleRowSpacing: CGFloat = 3
            static let titlePrimarySize: CGFloat = 20
            static let titleSecondarySize: CGFloat = 12
            static let profileAvatarScale: CGFloat = 0.88
        }

        enum MapCard {
            /// Fixed height SoT @ logicalWidth 393 (Android mirrors as dp).
            /// Derived: min(377×4/3, 780×0.48) = 374.4 — do not recompute at runtime.
            static let height: CGFloat = 374.4
            /// Historical aspect helper (width/height inverse = 4/3). Kept for notes only.
            static let widthOverHeightInverse: CGFloat = 4.0 / 3.0
            static let maxViewportFraction: CGFloat = 0.48
            static let cornerRadius: CGFloat = 14
        }
    }

    // MARK: - Collection (records list)

    enum Collection {
        static let horizontalPadding: CGFloat = 20

        enum TabBar {
            static let verticalPadding: CGFloat = 8
            static let capsuleHeight: CGFloat = 64
            static let capsuleInset: CGFloat = 8
            static let glassSpacing: CGFloat = 12
            static let iconSize: CGFloat = 14
        }

        enum ListRow {
            static let thumbnail: CGFloat = 72
            static let thumbnailRadius: CGFloat = 12
            static let rowSpacing: CGFloat = 12
            static let titleMetaGap: CGFloat = 8
            static let chipGap: CGFloat = 6
            static let verticalPadding: CGFloat = 4
        }

        static let headerFadeExtension: CGFloat = 72
        static let headerSolidPortion: CGFloat = 0.1
    }
}
