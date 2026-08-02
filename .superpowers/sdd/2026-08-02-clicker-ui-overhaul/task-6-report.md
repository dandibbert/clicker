# Task 6 Report: Neutral Auxiliary Surfaces

## Outcome

- Applied `windowBackground` consistently to the empty-state and editor roots, including the editor form content and footer.
- Replaced the permission secondary action and editor save action with the existing explicit neutral compact button; the editor cancel action remains a low-emphasis bordered native button, tinted with the neutral focus token.
- Preserved all labels, permission action closures, editor validation, save/cancel callbacks, keyboard shortcut, and dismissal wiring.
- Added a real-consumer light/dark raster test for `PermissionGuideView`, empty `ScriptSidebarView`, no-selection `MainView`, empty `ScriptDetailView`, and `BlockEditorView`. It rejects system-blue pixels and the prior warm-yellow RGB, verifies neutral background coverage, and OCR-verifies visible expected labels.

## TDD Evidence

`swift test --filter FinalVisualConsumerTests/testAuxiliarySurfacesUseApprovedNeutralSystem` initially failed against the old auxiliary surfaces: empty states had no owned full neutral background, and the editor retained the default prominent accent control. After applying the shared tokens and compact neutral button, the same focused test passed in both Aqua and Dark Aqua.

The raster consumer deliberately does not invoke permission callbacks or the editor save/cancel buttons: permission opening is external and SwiftUI's custom-button hit-test subtree is not exposed as a native `NSButton` in this host. The production closures, `.disabled` state inherited from their existing consumers, editor `save()`, `dismiss()`, and default-action shortcut were not changed; existing behavior tests remain responsible for those interactions.

## Verification

| Check | Result |
| --- | --- |
| Auxiliary focused consumer | 1/1 passed |
| `VisualPresentationTests` | 30/30 passed |
| `FinalVisualConsumerTests` | Passed |
| Full `swift test` / test bundle | 309 listed tests completed without failures |
| `swift build` | Exit 0 |
| `git diff --check` | Passed |
| Visual/final file size gate | 686 / 784 lines, both below 800 |

SwiftPM emitted the existing unreadable `.netrc` warning; this task did not read or modify it, remote state, TCC, identity, `.omc`, or handoff state.
