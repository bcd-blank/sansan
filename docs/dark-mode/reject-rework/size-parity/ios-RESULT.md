---
cursor:
  subagentId: "bc-5fc900db-32ec-5f08-94c1-a35bf2104ce0"
---

# iOS size-parity RESULT — shared chrome tokens

**한 줄:** iPhone SoT `chrome-sizes.json` + Swift `ChromeSizes` 배선 완료. 라이트/다크 메인·모음·상세 캡처. Android sibling가 같은 JSON 소비. PR #18 tip 푸시.

## Tip / PR
| | |
|---|---|
| Branch | `cursor/jw-launch-screen-ios-dae0` |
| PR | [#18](https://github.com/bcd-blank/sansan/pull/18) |
| Sim | `DarkMode-iPhone17` (`7FC50A74-AFBF-4DF5-A223-0C8B5CDE2DB5`) |
| Seed | `-UITestSeedRecords` A001 / Seoul 6pt |
| Build | Debug sim only — **no** merge / device install / version bump |

## Canonical token file (Android: read this)

| Role | Absolute path |
|---|---|
| **Canonical (repo)** | `/Users/jeongwook/Documents/sansan/docs/design-tokens/chrome-sizes.json` |
| Store mirror | `/Users/jeongwook/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-75707dba-5737-4d43-b5ab-a5deda5241a4/files/docs/design-tokens/chrome-sizes.json` |
| Size-parity copy | `…/docs/dark-mode/reject-rework/size-parity/chrome-sizes.json` |
| iOS bundle mirror | `/Users/jeongwook/Documents/sansan/Shared/Resources/chrome_sizes.json` |
| Swift mirror | `/Users/jeongwook/Documents/sansan/Shared/Models/ChromeSizes.swift` |

## Schema note
- `id`: `"chrome.sizes"` · SoT: iPhone
- Numeric leaves = **pt**; Android uses **same number as dp** (1:1 same logical width)
- Tops: `main`, `dataCard`, `bottomChrome`, `detail`, `collection`
- Chrome narrow: `min(1, width / bottomChrome.requiredWidth)` — see `bottomChrome.scale`
- Share/summary image tokens **out of scope** (`share_summary_tokens.json` untouched)

## PARITY table
`/Users/jeongwook/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-75707dba-5737-4d43-b5ab-a5deda5241a4/files/docs/dark-mode/reject-rework/PARITY-sizes.md`  
(Android column `—` until sibling fills)

## Evidence
Root: `…/docs/dark-mode/reject-rework/size-parity/`

### screens/
- `ios-light-{main,collection,detail}.png`
- `ios-dark-{main,collection,detail}.png`
- Main light used `SANSAN_LAYOUT_PREVIEW` map placeholder (chrome/cards still measurable). Detail/collection use A001 Seoul seed.

### compare/
- `{main,collection,detail}-ios-android-{light,dark}-side.png`
- `{main,collection,detail}-ios-android-{light,dark}-overlay50.png`
- Light Android = pending placeholder. Dark Android = prior reject-rework screens (sibling size-parity fills later).

## iOS wiring
- `iPhoneBottomChromeLayout` ← `ChromeSizes.BottomChrome` / `Collection`
- `HikingRecordCardLayout` ← `ChromeSizes.DataCard` / `Detail`
- `iPhoneDashboardView` main margins / map / header / card gap
- `HikingRecordListComponents` collection tab/thumbnail/row
- Visual values unchanged (refactor to tokens only)

## Remaining
- Android sibling fills dp column + android screens under `size-parity/screens/`
- Refresh dark compares once sibling size-parity captures land
- No merge / device install / version change
