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
/// `nonisolated`: pure design tokens — safe across targets that differ on
/// `SWIFT_DEFAULT_ACTOR_ISOLATION` (MainActor vs none).
nonisolated enum ChromeSizes {
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
            /// iPhone 17 ref safe-area top (status / Dynamic Island). Overlay align uses title top, not 0.
            static let safeAreaTopInsetRefIPhone17: CGFloat = 59
            /// Brand title top Y from screen top @ iPhone 17 ref (measured; see chrome-sizes main.overlayAlign).
            static let titleTopYAtIPhone17Ref: CGFloat = 84
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

    // MARK: - Image-save settings preview (pager thumbs)
    // Mirror of docs/design-tokens/image-save-preview.json

    nonisolated enum ImageSavePreview {
        static let cardAspectWidth: CGFloat = 314
        static let cardAspectHeight: CGFloat = 510
        /// Gallery thumb corner (smaller than former full-bleed 24).
        static let pageCorner: CGFloat = 16
        /// Flat uniform dim over preview (NOT gradient). Under title + check.
        static let dimOpacity: CGFloat = 0.2
        /// Gallery title — scaled down from full-bleed 17 for ~42% width thumbs.
        static let titleSize: CGFloat = 13
        static let titleTop: CGFloat = 8
        static let titleLeading: CGFloat = 8
        static let selectedBadgeTop: CGFloat = 8
        static let selectedBadgeTrailing: CGFloat = 8
        static let selectedBadgeDiameter: CGFloat = 22
        static let selectedBadgeCheckSize: CGFloat = 11
        static let selectedBorderWidth: CGFloat = 2.5
        static let showsPageDots: Bool = false
        static let dotsTopGap: CGFloat = 22
        /// Card width as fraction of gallery content width (40–45%).
        static let cardWidthFraction: CGFloat = 0.42
        static let gap: CGFloat = 12
        static let leadingInset: CGFloat = 16
        static let trailingInset: CGFloat = 16
        /// Reference bitmap width for cropTopPx values.
        static let referenceBitmapWidth: CGFloat = 1206

        /// Crop top (px @ 1206-wide native save) after width-fit. No Y stretch.
        enum CropTopPxAt1206 {
            static let dataCard: CGFloat = 601
            static let simpleGrey: CGFloat = 80
            static let simpleColor: CGFloat = 80
        }
    }
}
