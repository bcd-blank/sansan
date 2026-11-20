---
cursor:
  subagentId: "bc-5fc900db-32ec-5f08-94c1-a35bf2104ce0"
---

# PARITY — chrome sizes (iPhone SoT)

Token source: [`docs/design-tokens/chrome-sizes.json`](../../design-tokens/chrome-sizes.json)  
Absolute (repo): `/Users/jeongwook/Documents/sansan/docs/design-tokens/chrome-sizes.json`  
Absolute (store): `/Users/jeongwook/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-75707dba-5737-4d43-b5ab-a5deda5241a4/files/docs/design-tokens/chrome-sizes.json`

Unit: iPhone **pt** = Android **dp** (1:1 at same logical width). Android column filled when sibling lands.

| Item | JSON path | iPhone (pt) | Android (dp) |
|---|---|---:|---:|
| Main horizontal margin | `main.horizontalMargin` | 16 | — |
| Main card gap | `main.cardGap` | 12 | — |
| Main / data card inner padding | `main.cardInnerPadding` / `dataCard.innerPadding` | 11 | — |
| Data card corner radius | `main.cardCornerRadius` / `dataCard.cornerRadius` | 14 | — |
| Main map card height | `main.mapCard.height` | 320 | — |
| Main map card corner radius | `main.mapCard.cornerRadius` | 16 | — |
| Header avatar | `main.headerBand.avatar` | 36 | — |
| Header brand title size | `main.headerBand.brandTitleSize` | 22 | — |
| Header weather button | `main.headerBand.weatherButton` | 40 | — |
| Header pad L/T/V | `main.headerBand.padding*` | 16 / 10 / 6 | — |
| Data card min height | `dataCard.minHeight` | 78 | — |
| Data card icon+label gap | `dataCard.iconLabelGap` | 5 | — |
| Data card icon box | `dataCard.iconBox` | 22 | — |
| Data card icon symbol | `dataCard.iconSymbol` | 11 | — |
| Data card row spacing | `dataCard.rowSpacing` | 6 | — |
| Data card label font | `dataCard.font.label` | 10 | — |
| Data card value font | `dataCard.font.value` | 22 | — |
| Data card unit font | `dataCard.font.unit` | 11 | — |
| Data card unit color | `dataCard.font.unitColor` | secondary (not tint) | — |
| Data card value alignment | `dataCard.layout` | trailing / right | — |
| Bottom chrome outer height | `bottomChrome.outerHeight` | 64 | — |
| Bottom chrome radius | `bottomChrome.radius` | 32 | — |
| Bottom chrome side inset | `bottomChrome.sideInset` | 20 | — |
| Bottom chrome bottom inset | `bottomChrome.bottomInset` | 26 | — |
| Bottom chrome scroll end buffer | `bottomChrome.scrollEndBuffer` | 16 | — |
| Floating chrome height | `bottomChrome.floatingHeight` | 90 | — |
| Start button width | `bottomChrome.startButton.width` | 127 | — |
| Start button height | `bottomChrome.startButton.height` | 64 | — |
| Start button label | `bottomChrome.startButton.labelSize` | 15 | — |
| Tab item min width | `bottomChrome.tabItemMinWidth` | 72 | — |
| Tab capsule inset | `bottomChrome.tabCapsuleInset` | 8 | — |
| Detail horizontal padding | `detail.horizontalPadding` | 8 | — |
| Detail content width inset | `detail.contentWidthInset` | 16 | — |
| Detail top padding | `detail.topPadding` | 6 | — |
| Detail section spacing | `detail.sectionSpacing` | 10 | — |
| Detail card grid spacing | `detail.cardGridSpacing` | 8 | — |
| Detail top trailing control | `detail.topButtons.minTouch` | 44 | — |
| Detail title icon box | `detail.titleCard.iconBox` | 28 | — |
| Detail title primary size | `detail.titleCard.titlePrimarySize` | 20 | — |
| Detail memo | `detail.memoCard` | embedded in title card | — |
| Detail map height | `detail.mapCard.height` | 374.4 | — |
| Detail map corner radius | `detail.mapCard.cornerRadius` | 14 | — |
| Detail top button center Y | `detail.layoutAnchors.topCircularButtonCenterY` | 80.8 | — |
| Detail title card top Y | `detail.layoutAnchors.titleCardTopY` | 122.3 | — |
| Collection tab bar vertical pad | `collection.tabBar.verticalPadding` | 8 | — |
| Collection tab capsule height | `collection.tabBar.capsuleHeight` | 64 | — |
| Collection list thumbnail | `collection.listRow.thumbnail` | 72 | — |
| Collection thumbnail radius | `collection.listRow.thumbnailRadius` | 12 | — |
| Collection list scroll extra | `bottomChrome.collection.listScrollExtra` | 4 | — |

## Evidence folder

`docs/dark-mode/reject-rework/size-parity/` — screens + compare (iOS fills first; Android sibling later).
