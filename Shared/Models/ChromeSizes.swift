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

    // MARK: - Settings Form insetGrouped chrome (v26 — shared; Android 1:1)
    // Mirror of docs/design-tokens/chrome-sizes.json → settingsGrouped

    nonisolated enum SettingsGrouped {
        static let cornerRadius: CGFloat = 10
        static let horizontalInset: CGFloat = 20

        enum Dark {
            /// Form page / between-sections background (#1C1C1E).
            static let pageBackgroundRGB: (r: Int, g: Int, b: Int) = (28, 28, 30)
            /// Inset grouped list card fill (#2C2C2E). Android MUST NOT use darker #1C1C1E.
            static let cardFillRGB: (r: Int, g: Int, b: Int) = (44, 44, 46)
            /// No border — elevation is fill vs page only.
            static let cardStrokeWidth: CGFloat = 0
        }

        enum Light {
            static let pageBackgroundRGB: (r: Int, g: Int, b: Int) = (242, 242, 247)
            static let cardFillRGB: (r: Int, g: Int, b: Int) = (255, 255, 255)
            static let cardStrokeWidth: CGFloat = 0
        }
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

        // MARK: Settings layout SoT (v24 — shared iPhone pt; Android 1:1 dp)
        /// Gap gallery bottom → section footer caption (listRowInsets.bottom).
        static let galleryToCaptionGap: CGFloat = 20
        /// Extra list section spacing after image-save before 「저장 · 공유 지도」.
        static let sectionSpacingToShareMap: CGFloat = 18
        /// Measured dens-norm expected gallery card height (aspect × fraction).
        static let galleryCardHeight: CGFloat = 236
        /// 「이미지 저장 방식」 title top → 「저장 · 공유 지도」 toggle card top.
        static let sectionTitleToShareMapToggleTop: CGFloat = 410
        /// Gallery card top → share-map toggle card top.
        static let galleryTopToShareMapToggleTop: CGFloat = 370
        /// Legacy JW side@1024 px refs (binding SoT is the pt fields above).
        static let galleryCardHeightAtSide1024Px: CGFloat = 295
        static let galleryTopToShareMapToggleCardAtSide1024Px: CGFloat = 407

        // MARK: Section footer typography SoT (v25 — Form footnote; Android 1:1 dp)
        /// Footnote size (UIFont.preferredFont .footnote @ default content size).
        static let sectionFooterFontSize: CGFloat = 13
        /// Footnote line height (pt); Android use exact dp lineHeight.
        static let sectionFooterLineHeight: CGFloat = 18
        /// Letter-spacing / tracking (pt). Form default = 0.
        static let sectionFooterTracking: CGFloat = 0
        /// Leading+trailing inset from screen edge to footer ink (measured dens-norm ≈32).
        static let sectionFooterHorizontalPadding: CGFloat = 32
        /// Wrap width at 402-pt logical width: 402 − 2×32.
        static let sectionFooterMaxTextWidth: CGFloat = 338

        /// Crop top (px @ 1206-wide native save) after width-fit. No Y stretch.
        enum CropTopPxAt1206 {
            static let dataCard: CGFloat = 601
            static let simpleGrey: CGFloat = 80
            static let simpleColor: CGFloat = 80
        }
    }
}
