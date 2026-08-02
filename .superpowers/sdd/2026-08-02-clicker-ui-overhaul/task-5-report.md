# Task 5 Report: Native Live Settings and Compact Shortcut Capture

## Outcome

- Replaced the old navigated recording sheet with independent live Settings content grouped under `通用` and `录制`.
- Removed the Done footer, safe-area inset, dismiss dependency, navigation chrome, and phase-driven closing behavior.
- Kept all three appearance choices live and persisted through the injected store.
- Added a low-emphasis native bordered `恢复默认设置` action that restores both appearance and recording-stop shortcut defaults.
- Kept the shortcut card as one real SwiftUI `Button`, compacted it to a stable 80pt height, and preserved all individual keycaps and both capture-state messages.
- Preserved the hidden local `CaptureKeyView` first responder, shortcut conflict persistence, and injected shortcut-store writes.
- Settings remain visible outside idle; appearance, capture, and reset controls disable, and an active local capture is cancelled without dismissing the window.

## TDD Evidence

### Live Settings RED

```sh
swift test --filter SettingsPresentationTests/testSettingsRendersLivePreferenceSectionsWithoutDoneFooter
```

The old consumer failed because rendered output lacked `通用` and `恢复默认设置` and still contained `完成`.

### Compact card RED

```sh
swift test --filter SettingsPresentationTests/testCompactShortcutCardKeepsFullCardHitTargetAndStableFrame
```

The initial consumer failed against the old card while trying to require a descendant `NSButton`, exposing a macOS SwiftUI runtime assumption rather than the intended visual regression. That assertion was corrected as described below. The final consumer verifies an 80pt hosted boundary (the old production minimum was 92pt), equal idle/capture geometry, five visible keycap boundaries from the real bitmap, and both real rendered instructions.

### Non-idle capture mutation check

Removing the phase-change cancellation made `testNonIdleSettingsRemainPresentedWithEditingDisabled` fail because `CaptureKeyView` remained first responder. Restoring the cancellation returned the focused test to green.

## Runtime and Test Migration Resolutions

### SwiftUI button boundary

macOS SwiftUI plain buttons do not reliably expose a descendant `NSButton`. The card therefore remains the real SwiftUI `Button`; its full-surface contract is proven by `ShortcutCaptureTests.testCaptureCardInvokesExactlyOneTapAcrossItsWholeSurface`, which clicks three separated card points and observes exactly one action per click. No AppKit compatibility wrapper or source reflection remains.

### Removed footer contracts

The obsolete `VisualPresentationTests` assertions for `RecordingSettingsFooter`, `_InsetViewModifier`, and fixed footer controls were removed. Their behavior is now covered by hosted/OCR/bitmap consumers in `SettingsPresentationTests` and `FinalVisualConsumerTests`. No dead production footer compatibility type remains.

## Verification

| Check | Result |
| --- | --- |
| Live Settings focused consumer | 1/1 passed |
| Compact shortcut card focused consumer | 1/1 passed |
| Reset/no-footer focused consumer | 1/1 passed |
| `SettingsPresentationTests` | 7/7 passed |
| `ShortcutCaptureTests` | 11/11 passed |
| `RecordingStopShortcutTests` | 5/5 passed |
| Required final visual consumer | 1/1 passed |
| `swift test` | 308/308 passed, 0 failures |
| `swift build` | Exit 0 |
| `git diff --check` | Passed |
| Swift files under 800 lines | Passed; largest is 723 lines |

SwiftPM emitted the existing unreadable `.netrc` warning. The task did not read or modify `.netrc`, remote, TCC, identity, `.omc`, or handoff state.

## Self-review

- The production diff is limited to live Settings layout/behavior and compact shortcut-card geometry.
- Appearance and shortcut persistence use the existing injected stores; conflict candidates still preserve the previously saved shortcut and display the validation message below the card.
- The appearance section and card top remain stable when validation copy changes.
- The reset control is a stable native bordered action but does not use the prominent primary fill.
- No source-reflection assertion substitutes for the new Settings consumers.
- No unrelated production behavior, remote state, or user data was changed.
