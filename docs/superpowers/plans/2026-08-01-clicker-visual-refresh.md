# Clicker Visual Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the approved Cursor Trail macOS app icon and rebuild Clicker’s SwiftUI interface around an adaptive warm-white/charcoal/red visual system with recording and playback as equal primary actions.

**Architecture:** Keep all recording, playback, persistence, and permission behavior in the existing `AppState`; add small pure presentation models for deterministic state-to-copy/style decisions and focused SwiftUI components that consume them. Store the icon as maintainable SVG, generate the standard iconset and `.icns` through a parameterized local script, and make the existing app-bundle script include and declare that resource.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, XCTest, shell, SVG, `sips`, `iconutil`, Swift Package Manager, macOS 14+.

## Global Constraints

- Strict TDD: add the focused test and run it to a behavioral/compilation RED before changing the corresponding production code.
- Use the approved Cursor Trail icon: warm-white rounded square, black pointer, restrained red trail and endpoint, no text, no record/play symbol collage.
- Use the approved Refined Split layout with medium density.
- Recording and playback must live in the same primary-action component with equal dimensions and hierarchy.
- Follow macOS light/dark appearance; red is reserved for recording, destructive actions, active trail, and critical state.
- Respect macOS Reduce Motion; nonessential animation becomes static feedback.
- Preserve recording, playback, persistence, permission, editing, keyboard focus, and context-menu behavior.
- Do not add third-party dependencies or fonts.
- Automated tests must not activate real applications, change TCC, or post real keyboard/mouse input.
- Do not modify TCC, `.netrc`, or Git identity; do not perform remote Git operations.
- Keep `.omc/` and `docs/superpowers/clicker-handoff.md` untracked and never stage them.
- Stage exact task files only; never use `git add -A` or `git add .`.
- Use Conventional Commits.
- Keep every Swift file below 800 lines.
- After every task, report focused test, Debug build, file-size, diff-check, and `git status --short --branch` evidence.
- Stop completed, failed, or genuinely unresponsive agents promptly; do not run implementation agents in parallel.

---

## File Structure

- Create `Resources/AppIcon.svg`: maintainable approved Cursor Trail vector source.
- Create `scripts/build-icon.sh`: render SVG, generate all required iconset PNGs, and compile `.icns` to a caller-provided output.
- Modify `scripts/build-app.sh`: build/copy `Clicker.icns` and add `CFBundleIconFile` to the generated plist.
- Create `Tests/ClickerTests/AppIconAssetTests.swift`: exercise the icon builder in a temporary directory and verify exact representations.
- Create `Sources/Clicker/UI/ClickerVisualTheme.swift`: dynamic semantic colors, spacing, radii, and reduced-motion-aware transition decisions.
- Create `Sources/Clicker/UI/PrimaryActionBar.swift`: equal recording/playback state presentations and buttons.
- Create `Sources/Clicker/UI/ScriptHeaderView.swift`: title metadata, primary actions, and playback parameter strip.
- Create `Sources/Clicker/UI/ScriptSidebarView.swift`: brand header, script count, rows, and empty library state.
- Create `Sources/Clicker/UI/ClickerEmptyStateView.swift`: shared contextual empty-state shell.
- Create `Sources/Clicker/UI/ActionCardView.swift`: action icon, title, summary, duration, and active feedback.
- Create `Sources/Clicker/UI/PresentationModels.swift`: pure, Equatable state-to-presentation models consumed by the new views.
- Modify `Sources/Clicker/UI/MainView.swift`: apply the visual shell and refreshed permission guide.
- Modify `Sources/Clicker/UI/ScriptListView.swift`: delegate visual content to the sidebar components while retaining mutations.
- Modify `Sources/Clicker/UI/ScriptDetailView.swift`: compose header, parameter strip, cards, and bottom add-action menu.
- Modify `Sources/Clicker/UI/BlockRowView.swift`: replace with, or reduce to a compatibility wrapper around, `ActionCardView`.
- Modify `Sources/Clicker/UI/RecordingSettingsView.swift`: apply shared surfaces, hierarchy, and copy.
- Create `Tests/ClickerTests/VisualPresentationTests.swift`: test semantic action, sidebar, empty-state, theme, and motion decisions without UI introspection dependencies.
- Create `Tests/ClickerTests/ActionCardPresentationTests.swift`: test every block presentation and active-state decision against real `ActionBlock` values.

### Task 1: Cursor Trail Icon Pipeline and Bundle Integration

**Files:**
- Create: `Resources/AppIcon.svg`
- Create: `scripts/build-icon.sh`
- Modify: `scripts/build-app.sh`
- Create: `Tests/ClickerTests/AppIconAssetTests.swift`

**Interfaces:**
- Produces: `scripts/build-icon.sh <svg-source> <icns-output>`.
- Produces: `dist/Clicker.app/Contents/Resources/Clicker.icns`.
- Produces plist declaration: `CFBundleIconFile = Clicker`.
- The script uses a temporary directory, `sips` to rasterize/resize, and `iconutil -c icns`; it does not modify the source SVG.

- [ ] **Step 1: Write the failing icon-builder test**

Create an XCTest that locates the repository from `#filePath`, runs the requested script into a UUID temporary directory, and verifies the output using AppKit:

```swift
func testIconBuilderProducesStandardMacRepresentations() throws {
    let root = repositoryRoot()
    let output = temporaryDirectory.appendingPathComponent("Clicker.icns")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [
        root.appendingPathComponent("scripts/build-icon.sh").path,
        root.appendingPathComponent("Resources/AppIcon.svg").path,
        output.path,
    ]
    try process.run()
    process.waitUntilExit()

    XCTAssertEqual(process.terminationStatus, 0)
    let image = try XCTUnwrap(NSImage(contentsOf: output))
    let pixelWidths = Set(image.representations.map(\.pixelsWide))
    XCTAssertTrue(Set([16, 32, 128, 256, 512, 1024]).isSubset(of: pixelWidths))
}
```

Also assert that the SVG exists, contains a `viewBox="0 0 1024 1024"`, and that the generated `.icns` is nonempty. The SVG text assertion guards the public asset contract; visual correctness is handled by render/manual review.

- [ ] **Step 2: Run the focused test and capture RED**

Run: `swift test --filter AppIconAssetTests`

Expected: FAIL because `Resources/AppIcon.svg` and `scripts/build-icon.sh` do not exist.

- [ ] **Step 3: Add the approved SVG and minimal icon builder**

Create a 1024-square SVG with these literal design values:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <rect width="1024" height="1024" rx="220" fill="#F1EADC"/>
  <path d="M314 238 L742 526 L532 577 L423 786 Z" fill="#171619"/>
  <path d="M570 318 C724 350 813 439 820 586" fill="none"
        stroke="#E73836" stroke-width="58" stroke-linecap="round"/>
  <circle cx="822" cy="631" r="48" fill="#E73836"/>
</svg>
```

Implement `build-icon.sh` with `set -euo pipefail`, exact argument validation, a `mktemp -d` workspace cleaned by `trap`, one 1024 PNG rendered from SVG, the ten standard iconset filenames, and `iconutil -c icns` to the requested output. Do not use or modify TCC/signing configuration.

- [ ] **Step 4: Make the bundle consume the icon**

In `build-app.sh`, call:

```bash
./scripts/build-icon.sh Resources/AppIcon.svg "$APP/Contents/Resources/Clicker.icns"
```

Add `<key>CFBundleIconFile</key><string>Clicker</string>` to the generated plist before codesigning.

- [ ] **Step 5: Run focused test, build, and bundle verification**

Run:

```bash
swift test --filter AppIconAssetTests
swift build
./scripts/build-app.sh
test -s dist/Clicker.app/Contents/Resources/Clicker.icns
test "$(plutil -extract CFBundleIconFile raw -o - dist/Clicker.app/Contents/Info.plist)" = "Clicker"
codesign --verify --deep --strict --verbose=2 dist/Clicker.app
```

Expected: icon tests PASS, Debug build succeeds, icon exists, plist value matches, and signature verifies.

- [ ] **Step 6: Verify sizes, diff, and Git state**

Run: `wc -l Tests/ClickerTests/AppIconAssetTests.swift && git diff --check && git status --short --branch`

Expected: Swift file below 800 lines; only Task 1 files plus the two required untracked paths appear.

- [ ] **Step 7: Commit icon pipeline**

```bash
git add Resources/AppIcon.svg scripts/build-icon.sh scripts/build-app.sh Tests/ClickerTests/AppIconAssetTests.swift
git commit -m "feat: add clicker app icon"
```

### Task 2: Visual Theme and Pure Presentation Models

**Files:**
- Create: `Sources/Clicker/UI/ClickerVisualTheme.swift`
- Create: `Sources/Clicker/UI/PresentationModels.swift`
- Create: `Tests/ClickerTests/VisualPresentationTests.swift`

**Interfaces:**
- Produces: `enum ClickerVisualTheme` with semantic `Color` values, spacing, card radius, and primary control height.
- Produces: `enum PrimaryActionKind { case record, play }`.
- Produces: `struct PrimaryActionPresentation: Equatable` with `kind`, `title`, `systemImage`, `isStop`, `isEnabled`, and `accessibilityLabel`.
- Produces: `static func pair(phase: AppPhase, hasPlayableScript: Bool) -> [PrimaryActionPresentation]` returning record first and play second with equal hierarchy.
- Produces: `static func usesAnimatedActiveFeedback(isReduceMotionEnabled: Bool) -> Bool`.

- [ ] **Step 1: Write failing presentation tests**

Test exact state mappings:

```swift
func testIdlePrimaryActionsHaveEqualRecordAndPlaybackEntries() {
    let pair = PrimaryActionPresentation.pair(phase: .idle, hasPlayableScript: true)
    XCTAssertEqual(pair.map(\.kind), [.record, .play])
    XCTAssertEqual(pair.map(\.title), ["录制", "回放"])
    XCTAssertEqual(pair.map(\.isEnabled), [true, true])
    XCTAssertTrue(pair.allSatisfy { !$0.isStop })
}

func testRecordingAndPlaybackExposeExplicitStopCopy() {
    XCTAssertEqual(
        PrimaryActionPresentation.pair(phase: .recording, hasPlayableScript: true)[0].title,
        "停止录制"
    )
    XCTAssertEqual(
        PrimaryActionPresentation.pair(
            phase: .playing(iteration: 1, currentBlockID: nil),
            hasPlayableScript: true
        )[1].title,
        "停止回放"
    )
}
```

Cover countdown, non-playable script, the opposite action disabled during an active session, distinct accessibility labels, and reduce-motion true/false.

- [ ] **Step 2: Run tests and capture RED**

Run: `swift test --filter VisualPresentationTests`

Expected: FAIL to compile because the theme and presentation models do not exist.

- [ ] **Step 3: Implement minimal pure models and semantic theme**

Map all `AppPhase` cases explicitly. Use semantic/dynamic colors built from `NSColor(name:dynamicProvider:)` or appearance-aware SwiftUI colors; define red accent, surfaces, primary text, secondary text, separators, selection, record fill, playback fill, and active-trail colors. Define literal layout tokens: spacing 4/8/12/16/24, card radius 10, panel radius 14, primary control height 34.

- [ ] **Step 4: Run focused tests and Debug build**

Run: `swift test --filter VisualPresentationTests && swift build`

Expected: presentation tests PASS and Debug build succeeds.

- [ ] **Step 5: Verify sizes and commit**

Run: `wc -l Sources/Clicker/UI/ClickerVisualTheme.swift Sources/Clicker/UI/PresentationModels.swift Tests/ClickerTests/VisualPresentationTests.swift && git diff --check && git status --short --branch`

```bash
git add Sources/Clicker/UI/ClickerVisualTheme.swift Sources/Clicker/UI/PresentationModels.swift Tests/ClickerTests/VisualPresentationTests.swift
git commit -m "feat: add adaptive visual presentation system"
```

### Task 3: Branded Sidebar and Shared Empty States

**Files:**
- Create: `Sources/Clicker/UI/ScriptSidebarView.swift`
- Create: `Sources/Clicker/UI/ClickerEmptyStateView.swift`
- Modify: `Sources/Clicker/UI/ScriptListView.swift`
- Modify: `Sources/Clicker/UI/MainView.swift`
- Modify: `Sources/Clicker/UI/PresentationModels.swift`
- Modify: `Tests/ClickerTests/VisualPresentationTests.swift`

**Interfaces:**
- Produces: `struct ScriptRowPresentation: Equatable` with name, metadata, and accessibility label.
- Produces: `enum ClickerEmptyStateKind { case emptyLibrary, noSelection, emptyScript }` and its presentation.
- `ScriptSidebarView` consumes the existing `AppState` selection/mutation behavior through bindings and closures; it does not own scripts.

- [ ] **Step 1: Add failing sidebar and empty-state tests**

Use real `Script` values and fixed dates:

```swift
func testScriptRowIncludesActionCountAndModifiedMetadata() {
    let script = Script(name: "网页发布", blocks: [.wait(WaitBlock(duration: 1))])
    let model = ScriptRowPresentation(script: script, now: script.modifiedAt)
    XCTAssertEqual(model.name, "网页发布")
    XCTAssertEqual(model.actionCountText, "1 个动作")
    XCTAssertTrue(model.accessibilityLabel.contains("网页发布"))
    XCTAssertTrue(model.accessibilityLabel.contains("1 个动作"))
}

func testEmptyLibraryOffersRecordingAction() {
    let model = ClickerEmptyStatePresentation(kind: .emptyLibrary)
    XCTAssertEqual(model.title, "还没有脚本")
    XCTAssertEqual(model.actionTitle, "开始录制")
}
```

Cover plural action counts, no-selection copy, and empty-script copy.

- [ ] **Step 2: Run focused tests and capture RED**

Run: `swift test --filter VisualPresentationTests`

Expected: FAIL because sidebar/empty-state presentations do not exist.

- [ ] **Step 3: Implement the pure presentations and SwiftUI components**

Build a branded sidebar header with a cursor-trail-inspired SF Symbol treatment, “Clicker”, “脚本库”, and count. Use `List(selection:)` and retain context menus, rename alert, record notification, phase-based mutation disabling, and selection tags from the existing view. Build `ClickerEmptyStateView` with icon/title/description/optional action closure and use it for the empty library and no-selection detail state.

- [ ] **Step 4: Apply the adaptive shell in MainView**

Keep permission routing, settings sheet, alerts, permission refresh, and split-view behavior unchanged. Set the sidebar ideal width to 240 and minimum to 210; keep the app minimum window at 760×480.

- [ ] **Step 5: Run tests and build**

Run: `swift test --filter VisualPresentationTests && swift test --filter AppState && swift build`

Expected: presentation/AppState tests PASS and Debug build succeeds.

- [ ] **Step 6: Verify and commit**

Run: `wc -l Sources/Clicker/UI/ScriptSidebarView.swift Sources/Clicker/UI/ClickerEmptyStateView.swift Sources/Clicker/UI/ScriptListView.swift Sources/Clicker/UI/MainView.swift && git diff --check && git status --short --branch`

```bash
git add Sources/Clicker/UI/ScriptSidebarView.swift Sources/Clicker/UI/ClickerEmptyStateView.swift Sources/Clicker/UI/ScriptListView.swift Sources/Clicker/UI/MainView.swift Sources/Clicker/UI/PresentationModels.swift Tests/ClickerTests/VisualPresentationTests.swift
git commit -m "feat: refresh script library sidebar"
```

### Task 4: Equal Primary Actions and Refined Script Header

**Files:**
- Create: `Sources/Clicker/UI/PrimaryActionBar.swift`
- Create: `Sources/Clicker/UI/ScriptHeaderView.swift`
- Modify: `Sources/Clicker/UI/ScriptDetailView.swift`
- Modify: `Tests/ClickerTests/VisualPresentationTests.swift`

**Interfaces:**
- Consumes: `PrimaryActionPresentation.pair(phase:hasPlayableScript:)` from Task 2.
- Produces: `PrimaryActionBar` with exactly two equal-width controls in record/play order.
- Produces: `ScriptHeaderView` with title, action count, safe estimated duration, equal actions, and the existing repeat/interval bindings.

- [ ] **Step 1: Add failing script-header metadata tests**

Add `ScriptHeaderPresentation` tests using a trailing-only and wait script:

```swift
func testHeaderReportsActionCountAndPlanDuration() {
    let script = Script(
        name: "日报流程",
        blocks: [.wait(WaitBlock(duration: 1.5))],
        trailingDelay: 0.5
    )
    let model = ScriptHeaderPresentation(script: script)
    XCTAssertEqual(model.title, "日报流程")
    XCTAssertEqual(model.actionCountText, "1 个动作")
    XCTAssertEqual(model.durationText, "约 2.0 秒")
}
```

Cover empty scripts and nonfinite-safe formatting.

- [ ] **Step 2: Run tests and capture RED**

Run: `swift test --filter VisualPresentationTests`

Expected: FAIL because `ScriptHeaderPresentation` does not exist.

- [ ] **Step 3: Implement the header model and equal action bar**

Use `BlockExpander.plan(for:)` for duration. Render both controls from the pair model with the same `.frame(minWidth: 108, minHeight: ClickerVisualTheme.primaryControlHeight)`. Post existing `.toggleRecord` and `.togglePlay` notifications. Use red for record/stop-recording and neutral high-contrast styling for play/stop-playback; preserve model-provided disabled states and add `.accessibilityLabel`/`.help`.

- [ ] **Step 4: Replace the old split toolbar/control bar**

Compose `ScriptHeaderView` at the top of `ScriptDetailView`; remove record/play toolbar items and the old `controlBar`. Preserve repeat count clamping, repeat-forever toggle, interval clamping, editor dismissal, and all action-list mutations.

- [ ] **Step 5: Run focused/full affected tests and build**

Run: `swift test --filter VisualPresentationTests && swift test --filter AppStatePlaybackTests && swift test --filter AppStateRecordingTests && swift build`

Expected: all focused suites PASS and Debug build succeeds.

- [ ] **Step 6: Verify and commit**

Run: `wc -l Sources/Clicker/UI/PrimaryActionBar.swift Sources/Clicker/UI/ScriptHeaderView.swift Sources/Clicker/UI/ScriptDetailView.swift && git diff --check && git status --short --branch`

```bash
git add Sources/Clicker/UI/PrimaryActionBar.swift Sources/Clicker/UI/ScriptHeaderView.swift Sources/Clicker/UI/ScriptDetailView.swift Tests/ClickerTests/VisualPresentationTests.swift
git commit -m "feat: align recording and playback controls"
```

### Task 5: Action Cards and Reduced-Motion Active Feedback

**Files:**
- Create: `Sources/Clicker/UI/ActionCardView.swift`
- Modify: `Sources/Clicker/UI/BlockRowView.swift`
- Modify: `Sources/Clicker/UI/ScriptDetailView.swift`
- Modify: `Sources/Clicker/UI/PresentationModels.swift`
- Create: `Tests/ClickerTests/ActionCardPresentationTests.swift`

**Interfaces:**
- Produces: `struct ActionCardPresentation: Equatable` initialized from a real `ActionBlock`.
- Fields: `systemImage`, `title`, `summary`, `trailingText`, `accessibilityLabel`.
- Produces: `enum ActiveFeedbackStyle { case staticHighlight, pulsingTrail }` selected from `isActive` and `accessibilityReduceMotion`.

- [ ] **Step 1: Write failing action presentation tests**

Create one literal fixture per block type and assert exact title/icon/summary/trailing text. Include:

```swift
func testWaitCardSeparatesTitleSummaryAndDuration() {
    let model = ActionCardPresentation(block: .wait(WaitBlock(duration: 1.25)))
    XCTAssertEqual(model.systemImage, "clock")
    XCTAssertEqual(model.title, "等待")
    XCTAssertEqual(model.trailingText, "1.3 秒")
    XCTAssertTrue(model.accessibilityLabel.contains("等待"))
}

func testReduceMotionUsesStaticActiveFeedback() {
    XCTAssertEqual(
        ActiveFeedbackStyle.resolve(isActive: true, reduceMotion: true),
        .staticHighlight
    )
}
```

Cover click, drag, move, scroll, type text truncation, shortcut, wait, inactive state, active animated state, and reduce-motion active state.

- [ ] **Step 2: Run tests and capture RED**

Run: `swift test --filter ActionCardPresentationTests`

Expected: FAIL because presentation and feedback types do not exist.

- [ ] **Step 3: Implement pure mapping and the card view**

Move formatting logic out of `BlockRowView` into `ActionCardPresentation`. Build a medium-density card with 30×30 semantic icon container, two-line middle content, stable trailing value column, card surface, and a 3-point red leading trail when active. Read `@Environment(\.accessibilityReduceMotion)` and use static emphasis when enabled; any pulse changes opacity only and never layout.

- [ ] **Step 4: Preserve list editing behavior**

Use `ActionCardView` in `ScriptDetailView` while retaining double-click edit, move, delete, copy, context menu, active block identity, insets, and fixed bottom add-action menu. Keep `BlockRowView` only as a thin wrapper if tests/call sites still require it; otherwise delete it and stage the deletion explicitly.

- [ ] **Step 5: Run tests and build**

Run: `swift test --filter ActionCardPresentationTests && swift test --filter AppState && swift build`

Expected: presentation and AppState tests PASS; Debug build succeeds.

- [ ] **Step 6: Verify and commit**

Run: `wc -l Sources/Clicker/UI/ActionCardView.swift Sources/Clicker/UI/PresentationModels.swift Sources/Clicker/UI/ScriptDetailView.swift Tests/ClickerTests/ActionCardPresentationTests.swift && git diff --check && git status --short --branch`

```bash
git add Sources/Clicker/UI/ActionCardView.swift Sources/Clicker/UI/BlockRowView.swift Sources/Clicker/UI/ScriptDetailView.swift Sources/Clicker/UI/PresentationModels.swift Tests/ClickerTests/ActionCardPresentationTests.swift
git commit -m "feat: add adaptive action cards"
```

### Task 6: Permission, Settings, and Remaining Empty-State Polish

**Files:**
- Modify: `Sources/Clicker/UI/MainView.swift`
- Modify: `Sources/Clicker/UI/RecordingSettingsView.swift`
- Modify: `Sources/Clicker/UI/ClickerEmptyStateView.swift`
- Modify: `Sources/Clicker/UI/ScriptDetailView.swift`
- Modify: `Sources/Clicker/UI/PresentationModels.swift`
- Modify: `Tests/ClickerTests/VisualPresentationTests.swift`

**Interfaces:**
- Adds presentation kinds for permission-required and empty-script states.
- Preserves the existing settings editor, shortcut capture, validation, dismissal, and permission actions.

- [ ] **Step 1: Add failing permission/empty-script copy tests**

```swift
func testPermissionPresentationKeepsPrimaryAndSecondaryActions() {
    let model = ClickerEmptyStatePresentation(kind: .permissionRequired)
    XCTAssertEqual(model.title, "需要辅助功能权限")
    XCTAssertEqual(model.actionTitle, "打开系统设置")
    XCTAssertEqual(model.secondaryActionTitle, "重新检测")
}

func testEmptyScriptInvitesRecordingOrAddingAnAction() {
    let model = ClickerEmptyStatePresentation(kind: .emptyScript)
    XCTAssertEqual(model.title, "这个脚本还没有动作")
    XCTAssertEqual(model.actionTitle, "开始录制")
}
```

- [ ] **Step 2: Run tests and capture RED**

Run: `swift test --filter VisualPresentationTests`

Expected: FAIL because the new presentation kinds/actions do not exist.

- [ ] **Step 3: Apply shared visual language**

Replace the bespoke permission VStack with the shared empty-state shell and two action closures. Use the same theme in `RecordingSettingsView`: warm adaptive grouped surface, shortcut token, explicit primary “完成”, secondary “恢复默认值”, and unchanged warning behavior. In `ScriptDetailView`, show the empty-script state inside the content area while keeping the equal primary actions available.

- [ ] **Step 4: Run focused suites and build**

Run: `swift test --filter VisualPresentationTests && swift test --filter ShortcutCaptureTests && swift test --filter AppState && swift build`

Expected: all focused suites PASS and Debug build succeeds.

- [ ] **Step 5: Verify and commit**

Run: `wc -l Sources/Clicker/UI/MainView.swift Sources/Clicker/UI/RecordingSettingsView.swift Sources/Clicker/UI/ClickerEmptyStateView.swift Sources/Clicker/UI/ScriptDetailView.swift && git diff --check && git status --short --branch`

```bash
git add Sources/Clicker/UI/MainView.swift Sources/Clicker/UI/RecordingSettingsView.swift Sources/Clicker/UI/ClickerEmptyStateView.swift Sources/Clicker/UI/ScriptDetailView.swift Sources/Clicker/UI/PresentationModels.swift Tests/ClickerTests/VisualPresentationTests.swift
git commit -m "feat: unify clicker supporting screens"
```

### Task 7: Final Verification, Visual QA, and Local Bundle

**Files:**
- Modify only if a verified defect is found: exact responsible source/test files, with a new focused RED before production changes.
- Build artifact: `dist/Clicker.app`.

**Interfaces:**
- Verifies `docs/superpowers/specs/2026-08-01-clicker-visual-refresh-design.md` in full.
- Produces a locally runnable, ad-hoc-signed bundle with formal icon.

- [ ] **Step 1: Run complete tests and both builds**

Run: `swift test && swift build && swift build -c release`

Expected: all tests PASS and both configurations build. Record the exact XCTest count. Leave the existing `.netrc` warning untouched.

- [ ] **Step 2: Run structural gates**

Run:

```bash
find Sources Tests -name '*.swift' -print0 | xargs -0 wc -l | awk '$2 != "total" && $1 >= 800 { print; failed=1 } END { exit failed }'
git diff --check
```

Expected: no Swift file reaches 800 lines and no whitespace error appears.

- [ ] **Step 3: Rebuild and verify the app bundle**

Run:

```bash
./scripts/build-app.sh
plutil -lint dist/Clicker.app/Contents/Info.plist
test "$(plutil -extract CFBundleIconFile raw -o - dist/Clicker.app/Contents/Info.plist)" = "Clicker"
test -s dist/Clicker.app/Contents/Resources/Clicker.icns
codesign --verify --deep --strict --verbose=2 dist/Clicker.app
shasum -a 256 dist/Clicker.app/Contents/MacOS/Clicker
```

Expected: plist/icon assertions and strict signature verification pass; print the executable SHA-256.

- [ ] **Step 4: Render and inspect light/dark UI states**

Launch only the local built app without altering permissions. Capture screenshots for light and dark appearance at 760×480 minimum and a typical larger window, covering empty library, selected script with several block types, permission guide when safely observable, recording settings, and active playback presentation. Do not trigger real recording/playback solely for screenshots; use existing safe state injection in a test/debug preview if needed.

Check against the approved spec: Cursor Trail icon, Refined Split, medium density, equal record/play controls, semantic red, readable dark mode, stable active card, and no clipping. Record screenshot paths in the verification report; do not commit screenshots unless explicitly needed as maintained fixtures.

- [ ] **Step 5: Manual acceptance handoff**

Ask the user to verify Finder/Dock/app-switcher icon, system light/dark switching, window resizing, long-list scrolling, recording/countdown/playback/stop states, permission page, and settings sheet. Do not claim these pass without observation.

- [ ] **Step 6: Review Git evidence**

Run: `git log --oneline -10 && git status --short --branch && git diff HEAD~6..HEAD --stat`

Expected: task commits are present; only `.omc/` and `docs/superpowers/clicker-handoff.md` remain untracked; no staged or unrelated changes exist.

- [ ] **Step 7: Request final review**

Use `superpowers:requesting-code-review` for an architecture, accessibility, asset-pipeline, and visual-consistency review. Any Critical/Important behavioral defect requires a focused RED test before the fix, followed by focused/full verification and exact-file commit.
