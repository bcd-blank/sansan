---
cursor:
  subagentId: "bc-955b1e68-1973-58c6-b093-7e729cd7c717"
---

# iOS size-parity RESULT — detail map height SoT + pager gap fill

**한 줄:** PR #18 tip에 hangjunaru image-save pager/attribution merge + `detail.mapCard.height=374.4` 고정. A001 detail 라이트/다크 재캡처(상태바 13:56). Android는 같은 JSON 소비.

## Tip / PR
| | |
|---|---|
| Branch | `cursor/jw-launch-screen-ios-dae0` (push from worktree `cursor/ios-detail-mapheight-c717`) |
| Tip SHA | `31cf27d9ad418ceaa6b42e456bb4f1e2c5ee6d79` |
| PR | [#18](https://github.com/bcd-blank/sansan/pull/18) |
| Sim | `DarkMode-iPhone17` (`7FC50A74-AFBF-4DF5-A223-0C8B5CDE2DB5`) logical 402×874 @3x |
| Seed | `-UITestSeedRecords` A001 (`…a001`, 1.25km) |
| Status-bar clock | **13:56** (after tip commit) |
| Build | Debug sim only — **no** merge / device install / version bump |

## Branch gap check
| Ref | SHA | Result |
|---|---|---|
| Prior #18 tip | `822b727356b4b7fb4ab705f3b0fd235c283220e1` | Missing ImageSaveStylePager / hangjunaru previews / photo-toggle hide / attribution no-bg |
| Confirmed tip | `origin/cursor/ios-attribution-nobg-1cad` @ `fbe862f3f` | Merged onto #18 tip (merge `7bb55d2d1`) |
| Conflicts | AppStoreScreenshotMode, GeneralSettingsView, HikingRecordSummaryViews, HikingRecordsListView, iPhoneDashboardView | Newest confirmed: pager/attribution + keep #18 dark `mapStyle` + chrome tokens; keep `image-save`/`detail` screenshot modes |

## Detail map SoT
| Item | Value |
|---|---|
| `detail.mapCard.height` | **374.4** pt (=dp) |
| Derivation @393 | `min(377×4/3, 780×0.48)=374.4` |
| Aspect notes | kept; runtime uses **fixed height only** |
| `topCircularButtonCenterY` | **80.8** pt (screen-top, status-bar inclusive) |
| `titleCardTopY` | **122.3** pt |
| Measured map (dark) | ≈374.3 pt |

## Data Card preview aspect
| | |
|---|---|
| Preview bitmap | `data-card.png` **1206×1959** → aspect **0.6156** |
| Card frame | **314∶510** → aspect **0.6157** |
| Display | `scaledToFit` in equal-aspect card — **no stretch**; three pager cards equal size |

## Canonical token file (Android: read this)
| Role | Absolute path |
|---|---|
| **Canonical (repo)** | `/Users/jeongwook/Documents/sansan-보관/작업복사본-iOS/sansan-ios-detail-mapheight-c717/docs/design-tokens/chrome-sizes.json` |
| Store mirror | `/Users/jeongwook/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-75707dba-5737-4d43-b5ab-a5deda5241a4/files/docs/design-tokens/chrome-sizes.json` |
| Size-parity copy | `/Users/jeongwook/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-75707dba-5737-4d43-b5ab-a5deda5241a4/files/docs/dark-mode/reject-rework/size-parity/chrome-sizes.json` |
| iOS bundle mirror | `/Users/jeongwook/Documents/sansan-보관/작업복사본-iOS/sansan-ios-detail-mapheight-c717/Shared/Resources/chrome_sizes.json` |
| Swift | `/Users/jeongwook/Documents/sansan-보관/작업복사본-iOS/sansan-ios-detail-mapheight-c717/Shared/Models/ChromeSizes.swift` → `Detail.MapCard.height` |

## Evidence screens
- `/Users/jeongwook/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-75707dba-5737-4d43-b5ab-a5deda5241a4/files/docs/dark-mode/reject-rework/size-parity/screens/ios-light-detail.png`
- `/Users/jeongwook/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-75707dba-5737-4d43-b5ab-a5deda5241a4/files/docs/dark-mode/reject-rework/size-parity/screens/ios-dark-detail.png`
- `/Users/jeongwook/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-75707dba-5737-4d43-b5ab-a5deda5241a4/files/docs/dark-mode/reject-rework/size-parity/screens/ios-light-settings-image-save.png` (일반설정 image-save pager)
- `/Users/jeongwook/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-75707dba-5737-4d43-b5ab-a5deda5241a4/files/docs/dark-mode/reject-rework/size-parity/screens/ios-dark-settings-image-save.png`

## Remaining
- Android sibling remirrors `detail.mapCard.height` + layoutAnchors; settings side compares can use iOS settings captures above
- No merge / device install / version change
