# Task 4 Report: Separated Action Rows and Bottom Add Action

## Outcome

- Replaced inactive action cards with flat 56pt rows.
- Retained the distinct 30pt icon surface.
- Kept the subtle selection background and 3pt leading trail only for the active row.
- Added visible tinted list separators and 22pt horizontal row insets.
- Added a fixed, full-width 48pt “添加动作” bar with 22pt horizontal padding.
- Preserved double-click, Return, Space, VoiceOver edit action, context menu, move, and delete behavior.
- Added an explicit rectangular hit-test surface after removing the opaque card background.

## TDD Evidence

### Separated rows RED

Command:

```text
swift test --filter FinalVisualConsumerTests/testActionsRenderAsSeparatedRowsWithoutOuterCards
```

Observed against the original rounded-card implementation:

- Exit code: 1.
- Four real bitmap corner checks failed: only 0.8056–0.8210 of each sampled outer corner matched the list background.
- The real rendered stack had no visible separator between rows.

This was a behavior/bitmap failure, not source reflection.

### Separated rows GREEN

The same command passed after the minimal row styling change. The test renders the real `ScriptDetailView` at 600pt width and verifies:

- Both real `NSOutlineView` rows are 54–64pt high.
- Full-row outer corners remain the list background and contain no rounded separator-colored stroke.
- A visible separator exists between rows.
- The distinct icon surface resolves to 29–31pt in both dimensions.

### Bottom bar RED

Command:

```text
swift test --filter FinalVisualConsumerTests/testBottomAddActionBarStaysFixedEnabledAndClearOfLastRow
```

Observed against the original 12pt padded safe-area bar:

- Exit code: 1.
- At y=433 in the real 760×480 bitmap, all three full-width samples remained closer to canvas than to the bar surface (`0.00655` versus `0.03008`).
- The old bar therefore did not begin within the required bottom 48pt boundary.

### Bottom bar GREEN

The same command passed after applying the fixed 48pt bar. It verifies:

- The real add-action `NSButton` is contained in the bottom 48pt.
- The bar is full-width, begins inside the bottom 48pt, and does not extend above it.
- The native button is enabled in idle, disabled while `state.canEditScripts` is false, and re-enabled on return to idle.
- After scrolling a 12-row real list to the end, the last row remains above the fixed bar.

## Mutation and Regression Checks

- The initial RED run exercised the exact production mutation named in the brief: the pre-change rounded outer stroke caused the bitmap corner assertions to fail.
- The prior light-card boundary test was inverted to require canvas continuity, so restoring the old top border fails it.
- Removing the old opaque row surface exposed a real hit-testing regression: the focused double-click test stalled because the transparent spacer no longer formed a whole-row target. Adding `contentShape(Rectangle())` restored the full row; the exact test then passed in 0.192 seconds.
- `ActionCardPresentationTests` passed 19/19, covering double-click and the retained Return/Space/VoiceOver edit configuration.
- Context menu, move, and delete modifiers remain unchanged in `ScriptDetailView`; the full timeline mutation suite also passed.

## Verification

| Check | Result |
| --- | --- |
| Separated-row focused test | 1/1 passed |
| Bottom-bar focused test | 1/1 passed |
| `ActionCardPresentationTests` | 19/19 passed |
| `FinalVisualConsumerTests` | 8/8 passed |
| `swift test` | 308/308 passed, 0 failures |
| `swift build` | Exit 0 |
| Swift files under 800 lines | Passed; largest touched test file is 783 lines |
| `git diff --check` | Passed |

SwiftPM emitted its existing failed `.netrc` load warning during commands. No `.netrc`, remote, TCC, identity, `.omc`, or handoff state was read or modified by this task.

## Self-review

- Scope is limited to the two Task 4 production views, their two directly relevant test files, and this report.
- No model, persistence, playback, recording, or mutation behavior changed.
- Inactive rows have no outer fill or stroke; active selection and the leading trail remain conditional on playback state.
- The fixed bar uses existing spacing tokens for its 48pt height and continues to use `state.canEditScripts` as its enablement source.
- No destructive operations, remote operations, or unrelated cleanup were performed.

## Review Fix Round 1/5

### Active and inactive row coverage

The real 600pt `ScriptDetailView` fixture now enters playback with the first of two visible blocks active. The same bitmap therefore proves both sides of the state contract at once:

- The active row body resolves to the selection surface.
- Its leading trail renders at exactly 3.0pt wide and 48.0pt high; the anti-aliased assertion allows only 2.5–3.5pt width.
- The inactive row remains canvas-colored and has neither selection pixels nor any red active trail.

Mutation command:

```text
swift test --filter FinalVisualConsumerTests/testActionsRenderAsSeparatedRowsWithoutOuterCards
```

With `currentBlockID` temporarily changed to `nil`, the test failed for the intended reasons:

- Active selection fraction was `0.0`, below the required `0.9`.
- The active trail bitmap bounds were absent.

Restoring `currentBlockID` to the first block made those new assertions pass. That stronger fixture also exposed that the system List separator disappeared next to an active row: its detected span was only 9pt instead of more than 480pt. `ScriptDetailView` now owns a deterministic 1pt separator overlay between rows, and the full rendered-row test passes with active feedback present.

### Test support refactor

- Added `HostedScriptDetailFixture` to own the temporary script store, real `AppState`, hosted `ScriptDetailView`, window, settling, and cleanup.
- Both Task 4 consumer tests use the shared fixture instead of duplicating directory/state/window setup.
- Moved the Task 4 bitmap fraction, color-distance, and visible-role helpers into `FinalVisualConsumerTestSupport.swift`.
- `FinalVisualConsumerTests.swift` decreased from 783 to 703 lines despite adding the active/inactive assertions; its support file is 367 lines. Every Swift source and test file remains below 800 lines.

### Round 1 verification

| Check | Result |
| --- | --- |
| Active/inactive separated-row test | 1/1 passed |
| Bottom-bar test after fixture refactor | 1/1 passed |
| `ActionCardPresentationTests` | 19/19 passed |
| `FinalVisualConsumerTests` | 8/8 passed |
| `swift test` | 308/308 passed, 0 failures |
| `swift build` | Exit 0 |
| Swift files under 800 lines | Passed; Task 4 files are 703 and 367 lines |
| `git diff --check` | Passed |
