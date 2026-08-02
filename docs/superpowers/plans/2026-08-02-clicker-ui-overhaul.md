# Clicker UI Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Clicker’s default-looking main window and settings sheet with the approved compact, neutral macOS interface while adding a standard single-instance Settings window reachable from the gear button and `Command-,`.

**Architecture:** Keep `AppState` and all recording/playback behavior unchanged. Introduce explicit visual tokens and small SwiftUI presentation components, migrate settings to a `Settings` scene sharing the existing `AppState`, then verify real hosted controls and rendered output instead of asserting private view source structure.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, macOS 14+, XCTest, Vision OCR, Swift Package Manager.

## Global Constraints

- Swift 5.9, SwiftUI, AppKit, macOS 14+.
- Do not add third-party dependencies or fonts.
- Every production behavior change follows RED, GREEN, REFACTOR; run the named failing test before editing production code.
- Do not modify TCC, `.netrc`, Git identity, recording/playback engines, `AppState` business semantics, or script models.
- Do not perform remote Git operations.
- Keep `.omc/` and `docs/superpowers/clicker-handoff.md` untracked and unstaged.
- Keep every Swift file below 800 lines.
- Tests must not post real input, alter permissions, or activate external applications.
- Use exact-path staging and Conventional Commits.

## File Structure

- Modify `Sources/Clicker/App/ClickerApp.swift`: declare the main window and native `Settings` scene with the shared `AppState`.
- Modify `Sources/Clicker/UI/MainView.swift`: remove sheet ownership and consume an injected settings-opening action.
- Create `Sources/Clicker/UI/SettingsButton.swift`: icon-only gear control with stable accessibility semantics and a testable action boundary.
- Modify `Sources/Clicker/UI/ClickerVisualTheme.swift`: neutral light/dark semantic palette and compact geometry tokens.
- Modify `Sources/Clicker/UI/ClickerProminentButton.swift`: explicit compact record/playback styles without system accent blue.
- Modify `Sources/Clicker/UI/PrimaryActionBar.swift`: intrinsic-width 38pt peer actions.
- Modify `Sources/Clicker/UI/ScriptHeaderView.swift`: approved compact composite header.
- Modify `Sources/Clicker/UI/ScriptSidebarView.swift`: 230pt-oriented neutral sidebar and row selection presentation.
- Modify `Sources/Clicker/UI/ActionCardView.swift`: keep the existing public type names and change the consumer to a separated action row.
- Modify `Sources/Clicker/UI/ScriptDetailView.swift`: row separators/insets and compact bottom add-action bar.
- Modify `Sources/Clicker/UI/RecordingSettingsView.swift`: `ClickerSettingsView` becomes independent settings content with live controls and no footer.
- Modify `Sources/Clicker/UI/ShortcutKeycapView.swift`: compact full-width B-style shortcut capture card.
- Modify `Sources/Clicker/UI/ClickerEmptyStateView.swift` and `Sources/Clicker/UI/BlockEditorView.swift`: apply shared tokens without behavior changes.
- Create `Tests/ClickerTests/SettingsAccessTests.swift`: gear action and Settings root interaction boundary.
- Create `Tests/ClickerTests/EditorialMainWindowTests.swift`: hosted minimum-size main-window visual and hit-target evidence.
- Modify `Tests/ClickerTests/VisualPresentationTests.swift`: palette, action-row, empty-state, and editor render assertions.
- Modify `Tests/ClickerTests/SettingsPresentationTests.swift`: live settings rows and stable full-card capture behavior.
- Modify `Tests/ClickerTests/FinalVisualConsumerTests.swift`: replace obsolete compact-header/card expectations with approved final-consumer evidence.

---

### Task 1: Native Settings Entry Points

**Files:**
- Create: `Sources/Clicker/UI/SettingsButton.swift`
- Modify: `Sources/Clicker/App/ClickerApp.swift`
- Modify: `Sources/Clicker/UI/MainView.swift`
- Create: `Tests/ClickerTests/SettingsAccessTests.swift`

**Interfaces:**
- Produces: `SettingsButton(openSettings: @escaping () -> Void)`.
- Produces: `ClickerSettingsView` as the content of one SwiftUI `Settings` scene sharing the app’s existing `AppState`.
- Consumes: SwiftUI `@Environment(\.openSettings)` in `MainView`.

- [ ] **Step 1: Write the failing gear-action test**

Add a hosted-control test that renders the real button and proves its observable boundary:

```swift
@MainActor
func testIconOnlySettingsButtonInvokesInjectedOpenAction() throws {
    _ = NSApplication.shared
    var openCount = 0
    let hosting = NSHostingView(rootView: SettingsButton { openCount += 1 })
    hosting.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
    hosting.layoutSubtreeIfNeeded()

    let button = try XCTUnwrap(descendants(of: hosting).compactMap { $0 as? NSButton }.first)
    XCTAssertEqual(button.accessibilityLabel(), "设置")
    XCTAssertFalse(button.title.contains("设置"))
    button.performClick(nil)
    XCTAssertEqual(openCount, 1)
}
```

The production mutation caught is replacing the icon action with a no-op or rendering a text-labelled control.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter SettingsAccessTests/testIconOnlySettingsButtonInvokesInjectedOpenAction
```

Expected: compilation fails because `SettingsButton` does not exist.

- [ ] **Step 3: Implement the minimal icon-only action boundary**

Create `SettingsButton.swift`:

```swift
import SwiftUI

struct SettingsButton: View {
    let openSettings: () -> Void

    var body: some View {
        Button(action: openSettings) {
            Image(systemName: "gearshape")
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("设置")
        .help("设置")
    }
}
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 5: Write the failing shared-settings-root test**

Extend `SettingsAccessTests` by hosting the wished-for `ClickerSettingsView` with an injected state and selecting “浅色”; assert the same state instance changes to `.light`. This test must use the real segmented control and the real appearance store stub, following the existing `SettingsPresentationTests` interaction helper pattern.

Expected production mutation caught: constructing a separate `AppState` for Settings instead of injecting the app’s shared state.

- [ ] **Step 6: Run the new test and verify RED**

Run:

```bash
swift test --filter SettingsAccessTests/testClickerSettingsRootMutatesInjectedSharedState
```

Expected: compilation fails because `ClickerSettingsView` does not exist.

- [ ] **Step 7: Declare the native Settings scene and remove sheet state**

In `ClickerApp.body`, add:

```swift
Settings {
    ClickerSettingsView()
        .environmentObject(state)
        .preferredColorScheme(state.appearancePreference.colorScheme)
}
```

In `MainView`, remove `isShowingRecordingSettings` and `.sheet`. Read `@Environment(\.openSettings)` and pass `{ openSettings() }` into `SettingsButton`. Keep phase-based disabled semantics on the button, but do not close the Settings window when phase changes.

Declare `ClickerSettingsView` in `RecordingSettingsView.swift` as the dedicated Settings root that initially wraps the existing `RecordingSettingsView`; Task 5 replaces its internal layout. The `Settings` scene supplies the standard application-menu “设置…” item and `Command-,`; do not create a competing custom command.

- [ ] **Step 8: Verify tests and build**

Run:

```bash
swift test --filter SettingsAccessTests
swift test --filter SettingsPresentationTests
swift build
```

Expected: all selected tests pass and Debug build succeeds.

- [ ] **Step 9: Commit**

```bash
git add Sources/Clicker/App/ClickerApp.swift Sources/Clicker/UI/MainView.swift Sources/Clicker/UI/SettingsButton.swift Tests/ClickerTests/SettingsAccessTests.swift
git commit -m "feat: add native clicker settings window"
```

### Task 2: Neutral Visual Tokens and Compact Buttons

**Files:**
- Modify: `Sources/Clicker/UI/ClickerVisualTheme.swift`
- Modify: `Sources/Clicker/UI/ClickerProminentButton.swift`
- Modify: `Sources/Clicker/UI/PrimaryActionBar.swift`
- Modify: `Tests/ClickerTests/VisualPresentationTests.swift`
- Modify: `Tests/ClickerTests/FinalVisualConsumerTests.swift`

**Interfaces:**
- Produces token roles: `windowBackground`, `sidebarBackground`, `selection`, `controlSurface`, `focusRing`, `recordFill`, `playbackFill`.
- Produces geometry: `sidebarIdealWidth == 230`, `compactHeaderHeight` in `96...104`, `primaryControlHeight == 38`, `controlCornerRadius` in `6...10`.
- Produces `ClickerProminentButtonRole.recording` and `.neutral` with explicit non-system-accent rendering.

- [ ] **Step 1: Write failing palette behavior tests**

Add tests that resolve real colors under `.aqua` and `.darkAqua` and assert hand-derived properties:

```swift
func testOrdinarySelectionIsNeutralAndDistinctFromRecordingRed() throws {
    let aqua = try XCTUnwrap(NSAppearance(named: .aqua))
    let selection = ClickerVisualTheme.resolvedColor(for: .selection, appearance: aqua)
    let recording = ClickerVisualTheme.resolvedColor(for: .recordFill, appearance: aqua)
    XCTAssertLessThan(abs(selection.redComponent - selection.greenComponent), 0.06)
    XCTAssertLessThan(abs(selection.greenComponent - selection.blueComponent), 0.06)
    XCTAssertGreaterThan(recording.redComponent - recording.blueComponent, 0.35)
}

func testApprovedCompactGeometry() {
    XCTAssertEqual(ClickerVisualTheme.sidebarIdealWidth, 230)
    XCTAssertEqual(ClickerVisualTheme.primaryControlHeight, 38)
    XCTAssertTrue((96 ... 104).contains(ClickerVisualTheme.compactHeaderHeight))
}
```

The production mutations caught are reintroducing a blue selection token or oversized controls.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --filter VisualPresentationTests/testOrdinarySelectionIsNeutralAndDistinctFromRecordingRed
swift test --filter VisualPresentationTests/testApprovedCompactGeometry
```

Expected: FAIL because current selection is the card surface and primary controls are 44pt.

- [ ] **Step 3: Implement the semantic palette and geometry**

Update `ClickerVisualTheme` to use neutral light/dark RGB values. Use the approved roles instead of `Color.accentColor`; keep record red distinct. Set the geometry values from the Interfaces block. Preserve contrast tests for primary and secondary text.

- [ ] **Step 4: Write a failing real-button render test**

Render record and playback buttons at their intrinsic size in light and dark appearances. Inspect descendant `NSButton` frames and bitmap colors; assert both heights are 38pt, neither expands to 96pt width by default, the record control contains a red boundary cue, and playback contains a neutral high-contrast fill.

Expected production mutation caught: restoring `.borderedProminent` with system tint or the old full-width frame.

- [ ] **Step 5: Run the button test and verify RED**

Run:

```bash
swift test --filter FinalVisualConsumerTests/testPrimaryActionsRenderAsCompactPeerControls
```

Expected: FAIL because `PrimaryActionBar` currently enforces 96pt minimum width and 44pt height.

- [ ] **Step 6: Implement explicit compact styles**

Replace `.borderedProminent` with a plain button whose label owns its background, stroke, foreground and pressed/disabled opacity. Keep the native `Button` for accessibility. Remove `.frame(maxWidth: .infinity)` and the 96pt minimum from `PrimaryActionBar`; retain equal heights and peer visual weight.

- [ ] **Step 7: Verify focused suites and commit**

```bash
swift test --filter VisualPresentationTests
swift test --filter FinalVisualConsumerTests/testPrimaryActionsRenderAsCompactPeerControls
git add Sources/Clicker/UI/ClickerVisualTheme.swift Sources/Clicker/UI/ClickerProminentButton.swift Sources/Clicker/UI/PrimaryActionBar.swift Tests/ClickerTests/VisualPresentationTests.swift Tests/ClickerTests/FinalVisualConsumerTests.swift
git commit -m "feat: establish neutral clicker visual system"
```

### Task 3: Editorial Sidebar and Composite Header

**Files:**
- Modify: `Sources/Clicker/UI/MainView.swift`
- Modify: `Sources/Clicker/UI/ScriptSidebarView.swift`
- Modify: `Sources/Clicker/UI/ScriptHeaderView.swift`
- Create: `Tests/ClickerTests/EditorialMainWindowTests.swift`
- Modify: `Tests/ClickerTests/CompactHeaderPresentationTests.swift`
- Modify: `Tests/ClickerTests/FinalVisualConsumerTests.swift`

**Interfaces:**
- Consumes: Task 2 visual tokens and compact primary actions.
- Produces: `ScriptHeaderView` with title, metadata, peer actions and repeat parameters in one 96–104pt region.
- Produces: sidebar with ideal width 230pt and neutral selection rendering.

- [ ] **Step 1: Write the failing minimum-window consumer test**

Host the real `MainView` with two scripts at 760×480 in light mode. Use descendant `NSSplitView`, `NSButton`, `NSTextField` frames plus OCR to assert:

- sidebar width is between 210 and 250pt;
- “录制 1”, metadata, “录制”, “回放”, “重复”, “无限”, “间隔” and the gear button are visible inside the viewport;
- record and playback controls are 38pt high;
- the action-list content begins no lower than 152pt from the top of the content viewport.

The production mutation caught is the old 240pt-plus visual balance, oversized actions, or header content clipping.

- [ ] **Step 2: Run the consumer test and verify RED**

```bash
swift test --filter EditorialMainWindowTests/testApprovedMainWindowCompositionAtMinimumSize
```

Expected: FAIL on header/button geometry and neutral-selection expectations.

- [ ] **Step 3: Implement the sidebar and header composition**

Set `navigationSplitViewColumnWidth(min: 210, ideal: ClickerVisualTheme.sidebarIdealWidth, max: 250)`. In `ScriptHeaderView`, use the approved sequence:

```swift
HStack(spacing: 18) {
    identity.frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)
    PrimaryActionBar(...).fixedSize(horizontal: true, vertical: false)
    repeatParameters.fixedSize(horizontal: true, vertical: false)
}
.padding(.horizontal, 22)
.frame(height: ClickerVisualTheme.compactHeaderHeight)
```

Use a neutral selected row background supplied through list-row background or explicit row state; do not use `.tint(.blue)` or a blue semantic role. Preserve all context-menu behavior.

- [ ] **Step 4: Run the test and verify GREEN**

Run the Step 2 command. Expected: PASS.

- [ ] **Step 5: Cover extreme playback progress without restoring bulk**

Update the existing extreme finite/infinite playback fixtures to assert the title, actions, parameter controls and full progress label remain visible at 760×480 with the new geometry. Run the updated test before production adjustment; expected RED if progress crowds the header. Implement only the minimum layout priority or truncation change needed, then rerun to GREEN.

- [ ] **Step 6: Verify and commit**

```bash
swift test --filter EditorialMainWindowTests
swift test --filter CompactHeaderPresentationTests
swift test --filter FinalVisualConsumerTests
git add Sources/Clicker/UI/MainView.swift Sources/Clicker/UI/ScriptSidebarView.swift Sources/Clicker/UI/ScriptHeaderView.swift Tests/ClickerTests/EditorialMainWindowTests.swift Tests/ClickerTests/CompactHeaderPresentationTests.swift Tests/ClickerTests/FinalVisualConsumerTests.swift
git commit -m "feat: redesign clicker main window hierarchy"
```

### Task 4: Separated Action Rows and Bottom Add Action

**Files:**
- Modify: `Sources/Clicker/UI/ActionCardView.swift`
- Modify: `Sources/Clicker/UI/ScriptDetailView.swift`
- Modify: `Tests/ClickerTests/VisualPresentationTests.swift`
- Modify: `Tests/ClickerTests/ActionCardPresentationTests.swift`
- Modify: `Tests/ClickerTests/FinalVisualConsumerTests.swift`

**Interfaces:**
- Consumes: Task 2 tokens.
- Produces: real action row with no outer rounded-card stroke, stable active trail, double-click/keyboard/VoiceOver edit behavior.
- Produces: fixed compact “添加动作” bottom bar.

- [ ] **Step 1: Write a failing rendered-row test**

Render two real `ActionCardView` consumers in a 600pt-wide stack and assert their rows are 54–64pt high, the full-row outer corners contain the list background rather than a border color, a separator exists between rows, and the 30pt icon surface remains visible.

The production mutation caught is re-adding a rounded border around every action.

- [ ] **Step 2: Run the test and verify RED**

```bash
swift test --filter FinalVisualConsumerTests/testActionsRenderAsSeparatedRowsWithoutOuterCards
```

Expected: FAIL because each current action has a rounded background and stroke.

- [ ] **Step 3: Implement minimal row styling**

Remove the full-row `RoundedRectangle` background and stroke. Keep the icon surface. Use a subtle active background only when playing, place the 3pt trail at the leading edge, and let `ScriptDetailView` supply visible separators and 22pt horizontal insets.

- [ ] **Step 4: Verify row behavior and edit access**

```bash
swift test --filter FinalVisualConsumerTests/testActionsRenderAsSeparatedRowsWithoutOuterCards
swift test --filter ActionCardPresentationTests
```

Expected: PASS, including double-click, Return, Space and VoiceOver edit actions.

- [ ] **Step 5: Write and satisfy the bottom-bar hit-target test**

Host a script detail at 760×480 and assert the real add-action `NSButton` is inside the bottom 48pt, enabled only while `state.canEditScripts`, and the last list row remains scrollable above it. Run once before changing `ScriptDetailView`; expected RED against the old 12pt padded safe-area bar. Implement a 46–48pt tokenized bar and rerun to PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Clicker/UI/ActionCardView.swift Sources/Clicker/UI/ScriptDetailView.swift Tests/ClickerTests/VisualPresentationTests.swift Tests/ClickerTests/ActionCardPresentationTests.swift Tests/ClickerTests/FinalVisualConsumerTests.swift
git commit -m "feat: replace action cards with compact rows"
```

### Task 5: Native Settings Layout with B-Style Shortcut Capture

**Files:**
- Modify: `Sources/Clicker/UI/RecordingSettingsView.swift`
- Modify: `Sources/Clicker/UI/ShortcutKeycapView.swift`
- Modify: `Tests/ClickerTests/SettingsPresentationTests.swift`
- Modify: `Tests/ClickerTests/ShortcutCaptureTests.swift`
- Modify: `Tests/ClickerTests/FinalVisualConsumerTests.swift`

**Interfaces:**
- Consumes: the native Settings scene from Task 1 and token system from Task 2.
- Produces: live Settings content with “通用” and “录制” sections, no Done footer, low-emphasis reset action.
- Produces: full-width compact `ShortcutCaptureCard` whose frame is stable while capturing.

- [ ] **Step 1: Write failing live-settings layout tests**

Update the hosted 440×360 fixture to assert rendered text contains “通用”, “外观”, “录制”, “停止录制快捷键” and “恢复默认设置”, and does not contain “完成”. Assert there is no bottom safe-area footer and that all three appearance choices remain real selectable segments.

The production mutation caught is restoring the old form sheet/footer or losing live appearance controls.

- [ ] **Step 2: Run the tests and verify RED**

```bash
swift test --filter SettingsPresentationTests/testSettingsRendersLivePreferenceSectionsWithoutDoneFooter
```

Expected: FAIL because the current screen has “录制设置” navigation chrome and a Done footer.

- [ ] **Step 3: Implement independent live Settings content**

Remove `@Environment(\.dismiss)`, `NavigationStack`, `RecordingSettingsFooter`, and phase-triggered dismissal. Build two compact sections inside the Settings window. Keep appearance binding and shortcut editor persistence unchanged. Disable capture and editing while the phase is non-idle instead of closing the window.

- [ ] **Step 4: Write a failing B-style capture-card render test**

Render the real card before and during capture. Assert:

- the full card is one `NSButton` hit target;
- its height remains in 72–84pt and unchanged within 1pt;
- all keycaps stay visible;
- idle copy is “点击重新录入” and capture copy is “请按下新的组合键…”;
- the validation message remains below the card without moving the appearance section.

- [ ] **Step 5: Run the card test and verify RED**

```bash
swift test --filter SettingsPresentationTests/testCompactShortcutCardKeepsFullCardHitTargetAndStableFrame
```

Expected: FAIL because the current card is at least 92pt and uses the old spacing.

- [ ] **Step 6: Implement the compact full-card layout**

Keep `ShortcutKeycapPresentation`. Reduce card spacing and height, retain individual keycaps, use one subtle border, and keep `ShortcutCaptureView` as the hidden local-first-responder consumer only while `isCapturing`.

- [ ] **Step 7: Verify shortcut behavior and commit**

```bash
swift test --filter SettingsPresentationTests
swift test --filter ShortcutCaptureTests
swift test --filter RecordingStopShortcutTests
swift test --filter FinalVisualConsumerTests/testRecordingSettingsRendersAppearanceChoicesAndReplacesLegacyShortcutForm
git add Sources/Clicker/UI/RecordingSettingsView.swift Sources/Clicker/UI/ShortcutKeycapView.swift Tests/ClickerTests/SettingsPresentationTests.swift Tests/ClickerTests/ShortcutCaptureTests.swift Tests/ClickerTests/FinalVisualConsumerTests.swift
git commit -m "feat: modernize clicker settings layout"
```

### Task 6: Apply the System to Empty States and Editor

**Files:**
- Modify: `Sources/Clicker/UI/ClickerEmptyStateView.swift`
- Modify: `Sources/Clicker/UI/BlockEditorView.swift`
- Modify: `Tests/ClickerTests/VisualPresentationTests.swift`
- Modify: `Tests/ClickerTests/FinalVisualConsumerTests.swift`

**Interfaces:**
- Consumes: Task 2 tokens and compact button styles.
- Produces: consistent permission, empty-library, no-selection, empty-script and editor surfaces without business changes.

- [ ] **Step 1: Write failing final-surface render tests**

Render permission, empty library, no-selection, empty script and one representative block editor in both appearances. Assert each uses the neutral window background, has no system-blue primary action pixels, keeps expected labels visible, and preserves enabled/disabled hit targets.

The production mutation caught is a remaining default accent button or a screen-specific warm-yellow surface.

- [ ] **Step 2: Run tests and verify RED**

```bash
swift test --filter FinalVisualConsumerTests/testAuxiliarySurfacesUseApprovedNeutralSystem
```

Expected: FAIL on at least the editor’s default controls or an obsolete background token.

- [ ] **Step 3: Apply shared tokens only**

Replace ad hoc backgrounds, spacing and button styles in the two production views. Do not change labels, permission actions, edit validation, save/cancel semantics, or dismissal behavior.

- [ ] **Step 4: Verify and commit**

```bash
swift test --filter VisualPresentationTests
swift test --filter FinalVisualConsumerTests/testAuxiliarySurfacesUseApprovedNeutralSystem
git add Sources/Clicker/UI/ClickerEmptyStateView.swift Sources/Clicker/UI/BlockEditorView.swift Tests/ClickerTests/VisualPresentationTests.swift Tests/ClickerTests/FinalVisualConsumerTests.swift
git commit -m "feat: unify clicker auxiliary surfaces"
```

### Task 7: Final Regression, Bundle, and Manual Handoff

**Files:**
- Modify only if a failing regression requires a TDD fix; use the test and production file that own that behavior.
- Do not modify or stage `.omc/` or `docs/superpowers/clicker-handoff.md`.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: verified Debug/Release app bundle and explicit manual-test list.

- [ ] **Step 1: Run complete automated verification**

```bash
swift test
swift build
swift build -c release
find Sources Tests -name '*.swift' -print0 | xargs -0 wc -l | awk '$2 != "total" && $1 >= 800 { print; failed=1 } END { exit failed }'
git diff --check
```

Expected: all tests pass, both builds succeed, no Swift file reaches 800 lines, and diff check exits zero.

- [ ] **Step 2: Fix regressions only through a new RED/GREEN cycle**

For each failure, run its single focused test and confirm the failure. If the failure represents a real regression, add or refine the smallest behavior test, observe RED, implement the minimum correction, rerun focused GREEN, then rerun Step 1. Do not weaken OCR bounds or remove consumer assertions merely to obtain GREEN.

- [ ] **Step 3: Build and validate the application bundle**

```bash
./scripts/build-app.sh
plutil -lint dist/Clicker.app/Contents/Info.plist
test "$(plutil -extract CFBundleIconFile raw -o - dist/Clicker.app/Contents/Info.plist)" = "Clicker"
test -s dist/Clicker.app/Contents/Resources/Clicker.icns
codesign --verify --deep --strict --verbose=2 dist/Clicker.app
shasum -a 256 dist/Clicker.app/Contents/MacOS/Clicker
```

Expected: bundle rebuilt, plist valid, icon present, strict ad-hoc signature valid, and a fresh executable checksum printed.

- [ ] **Step 4: Record manual acceptance without overstating it**

Manually verify when the environment permits, and label anything not exercised as unverified:

- gear opens Settings; `Command-,` opens and refocuses the same Settings window;
- light, dark and follow-system appearance;
- keyboard focus, VoiceOver order and labels;
- largest accessibility text size and Reduce Motion;
- real record, countdown, stop, playback and long-list scrolling;
- 760×480 and typical larger window sizes.

- [ ] **Step 5: Commit any final test-only evidence and report status**

If Step 2 or manual-evidence fixtures created tracked changes, stage only those exact task files and commit:

```bash
git commit -m "test: verify clicker ui overhaul"
```

Then report:

```bash
git status --short --branch
git log -8 --oneline
git diff --stat HEAD~7..HEAD
```

Expected final untracked paths are only `.omc/` and `docs/superpowers/clicker-handoff.md`.
