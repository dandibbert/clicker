# Clicker Task 19B UI and Editor Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复动作块编辑的数据不变量，禁止回放期间修改脚本，并补齐空库录制入口、Carbon 热键注册错误展示和单主窗口语义。

**Architecture:** 将动作块编辑从 SwiftUI sheet 下沉到 `ClickerCore` 的纯函数，通过完整构造新值一次性替换旧块；`AppState` 负责编辑权限和错误发布，SwiftUI 只绑定纯编辑结果与状态。Carbon 注册函数保留在系统边界，但注册结果转换为可测试的结构化失败。

**Tech Stack:** Swift 5.9、SwiftUI、AppKit、Carbon HIToolbox、XCTest、Swift Package Manager；目标 macOS 14+。

## Global Constraints

- 严格 TDD：每个生产行为先写测试并观察预期失败，再写最小实现。
- 不做远程 Git 操作，不修改 TCC、`.netrc` 或 Git identity。
- 只精确暂存当前任务文件；`.omc/` 与 `docs/superpowers/clicker-handoff.md` 始终保持未跟踪。
- 不破坏 schema v4 绝对时间轴、稳定 ordinal、录制 cutoff、回放取消释放和事务持久化不变量。
- 所有 Swift 源码和测试文件少于 800 行。
- 每个提交前运行聚焦测试和 `git diff --check`；阶段结束运行完整 `swift test` 与 `swift build`。

---

## File Structure

- Create `Sources/ClickerCore/Editing/ActionBlockEditor.swift`: 纯动作块重建、有限非负时长规范化、轨迹平移/缩放和滚轮采样保留。
- Create `Tests/ClickerCoreTests/ActionBlockEditorTests.swift`: 每个已知编辑缺陷的手工推导回归测试。
- Modify `Sources/Clicker/UI/BlockEditorView.swift`: 采集表单值并调用不可变编辑函数，不再连续修改 payload。
- Modify `Sources/Clicker/App/AppState.swift`: 集中定义脚本能否编辑，并拒绝回放期间的更新、复制和删除；发布热键注册失败。
- Modify `Tests/ClickerTests/AppStatePlaybackTests.swift`: 验证活跃回放使用启动快照且期间写操作无效。
- Modify `Sources/Clicker/UI/ScriptDetailView.swift`: 禁用回放期间的表单、块编辑、增删复制和排序入口。
- Modify `Sources/Clicker/UI/ScriptListView.swift`: 空库显示可操作录制按钮，并禁用非 idle 阶段的库修改入口。
- Modify `Sources/Clicker/App/HotKeyCenter.swift`: 检查每次 `RegisterEventHotKey` 的 `OSStatus` 并返回结构化失败。
- Create `Tests/ClickerTests/HotKeyCenterTests.swift`: 通过注入注册函数验证成功与失败分类，不注册真实系统热键。
- Modify `Sources/Clicker/UI/MainView.swift`: 展示热键注册失败 alert。
- Modify `Sources/Clicker/App/ClickerApp.swift`: 发布启动注册失败，并使用单主 `Window` 场景。

---

### Task 1: Immutable Action Block Editing

**Files:**
- Create: `Tests/ClickerCoreTests/ActionBlockEditorTests.swift`
- Create: `Sources/ClickerCore/Editing/ActionBlockEditor.swift`

**Interfaces:**
- Consumes: `ClickBlock`, `MoveBlock`, `DragBlock`, `ScrollBlock`, `TypeTextBlock`, `ShortcutBlock`, `WaitBlock` and their persisted IDs, offsets, flags, coordinates, sample times, and ordinals.
- Produces: `public enum ActionBlockEditor` with `click`, `move`, `drag`, `scroll`, `typeText`, `shortcut`, and `wait` static reconstruction functions.

- [ ] **Step 1: Write failing click and shortcut fidelity tests**

Add tests that construct payloads with distinct release values, edit the visible values, and assert literal results:

```swift
func testClickEditMovesDownAndUpCoordinatesTogether() {
    let original = ClickBlock(x: 10, y: 20, button: .left, clickCount: 1,
                              duration: 0.25, upX: 11, upY: 21,
                              downOrdinal: 7, upOrdinal: 9)
    let edited = ActionBlockEditor.click(original, x: 30, y: 40,
                                         button: .right, clickCount: 2)
    XCTAssertEqual([edited.x, edited.y, edited.upX, edited.upY], [30, 40, 30, 40])
    XCTAssertEqual(edited.upClickCount, 2)
    XCTAssertEqual([edited.downOrdinal, edited.upOrdinal], [7, 9])
}

func testShortcutEditUsesSameModifiersForSafeKeyRelease() {
    let original = ShortcutBlock(keyCode: 8, flags: 1, upFlags: 2,
                                 duration: 0.4, downOrdinal: 4, upOrdinal: 6)
    let edited = ActionBlockEditor.shortcut(original, keyCode: 9, flags: 12)
    XCTAssertEqual(edited.flags, 12)
    XCTAssertEqual(edited.upFlags, 12)
    XCTAssertEqual([edited.downOrdinal, edited.upOrdinal], [4, 6])
}
```

- [ ] **Step 2: Run the click and shortcut tests and verify RED**

Run: `swift test --filter ActionBlockEditorTests`

Expected: compilation fails because `ActionBlockEditor` does not exist; this is the production symbol that will make the tests pass.

- [ ] **Step 3: Implement minimal immutable click and shortcut reconstruction**

Create `ActionBlockEditor` functions that call the full public payload initializers once, preserve identity/timeline/fidelity metadata, and deliberately synchronize click up coordinates/count and shortcut `upFlags` with the edited visible values.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run: `swift test --filter ActionBlockEditorTests`

Expected: both tests pass with no warnings.

- [ ] **Step 5: Write failing scroll preservation tests**

Use three literal `ScrollStep` samples with distinct `t`, location, `dx`, flags, and ordinals. Editing total `dy` from `-8` to `-16` must retain all three samples and all non-`dy` fields while producing literal `dy` values `[-4, -6, -6]`. Add a zero-total fixture whose edit changes only the last sample by the requested total, so opposite-direction samples are not discarded.

- [ ] **Step 6: Run the scroll tests and verify RED**

Run: `swift test --filter ActionBlockEditorTests/testScroll`

Expected: compilation or assertion failure because scroll editing is not implemented.

- [ ] **Step 7: Implement sample-preserving scroll editing and verify GREEN**

For nonzero original total, scale each `dy` by `newTotal / oldTotal`. For a zero-total nonempty sequence, add the requested delta to the last step. For an empty sequence, create one safe step at the block location. Rebuild `ScrollBlock` preserving duration and timeline metadata.

Run: `swift test --filter ActionBlockEditorTests`

- [ ] **Step 8: Write failing duration and drag safety tests**

Cover move, drag, and wait edits with `-1`, `.infinity`, and `.nan`, asserting a literal duration of `0` and finite point times. Cover a one-point drag edited from `(10, 20)` to `(30, 40)`, asserting two endpoints, a down at the edited start, an up at the edited end, and preserved `hasRecordedMouseUp`/`upOrdinal`.

- [ ] **Step 9: Run the duration and drag tests and verify RED**

Run: `swift test --filter ActionBlockEditorTests`

Expected: failures for missing normalization and one-point endpoint reconstruction.

- [ ] **Step 10: Implement move, drag, wait, and text reconstruction and verify GREEN**

Use a private finite/nonnegative time sanitizer. Rescale existing point times when duration changes; translate move coordinates to the requested endpoint; remap multi-point drag geometry; synthesize start/end points for one-point drag so `BlockExpander` always emits a release. Preserve IDs, offsets, flags, ordinals, and drag release metadata.

Run: `swift test --filter ActionBlockEditorTests`

- [ ] **Step 11: Commit the pure editing behavior**

```bash
git add Sources/ClickerCore/Editing/ActionBlockEditor.swift Tests/ClickerCoreTests/ActionBlockEditorTests.swift
git diff --cached --check
git commit -m "fix: preserve input fidelity while editing blocks"
```

---

### Task 2: Wire the Block Editor to Atomic Reconstruction

**Files:**
- Modify: `Sources/Clicker/UI/BlockEditorView.swift`
- Test: `Tests/ClickerCoreTests/ActionBlockEditorTests.swift`

**Interfaces:**
- Consumes: all `ActionBlockEditor` functions from Task 1 and the existing sheet state values.
- Produces: one fully rebuilt `ActionBlock` passed to `onSave`, with no intermediate mutable payload state.

- [ ] **Step 1: Add a failing whole-action dispatch test**

Add `ActionBlockEditor.edit(_:, values:)` coverage for representative click, scroll, and drag cases, using an `ActionBlockEditValues` value whose literal fields match the SwiftUI form. Assert the returned enum case and complete payload from Task 1.

- [ ] **Step 2: Run the dispatch test and verify RED**

Run: `swift test --filter ActionBlockEditorTests/testEditDispatches`

Expected: compilation failure because the whole-action edit interface is missing.

- [ ] **Step 3: Implement the minimal edit-values interface and verify GREEN**

Add a public `ActionBlockEditValues` value type and `ActionBlockEditor.edit(_:, values:)`. The dispatcher switches once and returns the corresponding immutable reconstruction.

Run: `swift test --filter ActionBlockEditorTests`

- [ ] **Step 4: Replace mutable sheet save logic**

Delete `BlockEditorView`'s local point rescaling and every `case .kind(var b)` assignment chain. Build one `ActionBlockEditValues` from form state and call `ActionBlockEditor.edit(block, values:)` before invoking `onSave`.

- [ ] **Step 5: Verify editor integration and commit**

Run: `swift test --filter ActionBlockEditorTests`

Run: `swift build`

```bash
git add Sources/ClickerCore/Editing/ActionBlockEditor.swift Tests/ClickerCoreTests/ActionBlockEditorTests.swift Sources/Clicker/UI/BlockEditorView.swift
git diff --cached --check
git commit -m "refactor: rebuild edited action blocks atomically"
```

---

### Task 3: Freeze Script Mutation During Playback

**Files:**
- Modify: `Tests/ClickerTests/AppStatePlaybackTests.swift`
- Modify: `Sources/Clicker/App/AppState.swift`
- Modify: `Sources/Clicker/UI/ScriptDetailView.swift`
- Modify: `Sources/Clicker/UI/ScriptListView.swift`

**Interfaces:**
- Consumes: `AppPhase`, synchronous `AppState.update`, `duplicateScript`, and `deleteScript`, plus the script value passed to `PlaybackControlling.play`.
- Produces: `AppState.canEditScripts: Bool`, true only in `.idle`; mutation methods reject non-idle changes while active playback keeps its original value snapshot.

- [ ] **Step 1: Write failing playback mutation tests**

Start playback with a script, then attempt update, duplicate, and delete. Assert the store received no save/delete, the in-memory library is unchanged, and `StubPlaybackEngine.playedScripts[0]` remains the exact pre-edit value. Also assert `canEditScripts` is false while playing and true after stop.

- [ ] **Step 2: Run the playback state tests and verify RED**

Run: `swift test --filter AppStatePlaybackTests`

Expected: update/duplicate/delete mutate the library or persist while playback is active, and `canEditScripts` is missing.

- [ ] **Step 3: Add the central mutation guard and verify GREEN**

Implement `canEditScripts` from `phase == .idle`; guard update, duplicate, and delete before any store operation. Keep playback input as the already-copied `Script` value.

Run: `swift test --filter AppStatePlaybackTests`

- [ ] **Step 4: Disable every SwiftUI mutation entry**

Use `state.canEditScripts` for repeat controls, double-click edit, context-menu edit/copy/delete, move/delete gestures, append menu, rename/copy/delete, and any open editor save. Identify edited blocks by block ID at save time so a stale index cannot target a different block.

- [ ] **Step 5: Verify and commit playback edit protection**

Run: `swift test --filter AppStatePlaybackTests`

Run: `swift build`

```bash
git add Tests/ClickerTests/AppStatePlaybackTests.swift Sources/Clicker/App/AppState.swift Sources/Clicker/UI/ScriptDetailView.swift Sources/Clicker/UI/ScriptListView.swift
git diff --cached --check
git commit -m "fix: freeze script editing during playback"
```

---

### Task 4: Keep a Recording Entry in an Empty Library

**Files:**
- Modify: `Tests/ClickerTests/AppStateRecordingTests.swift`
- Modify: `Sources/Clicker/App/AppState.swift`
- Modify: `Sources/Clicker/UI/ScriptListView.swift`

**Interfaces:**
- Consumes: existing `.toggleRecord` notification and `AppPhase`.
- Produces: `AppState.canStartRecording: Bool` and an empty-library button labeled `开始录制` which posts source `ui` and is disabled outside idle.

- [ ] **Step 1: Write and run the failing recording availability test**

Assert `canStartRecording` is true in idle and false in countdown, recording, and playing phases.

Run: `swift test --filter AppStateRecordingTests/testRecordingEntryAvailabilityFollowsPhase`

Expected: compilation failure because `canStartRecording` does not exist.

- [ ] **Step 2: Implement recording availability and verify GREEN**

Add the computed state policy and rerun `swift test --filter AppStateRecordingTests`.

- [ ] **Step 3: Wire the empty-state action**

Replace the passive `ContentUnavailableView` overlay with its actions form. The `开始录制` button posts `.toggleRecord` with `["source": "ui"]` and uses `canStartRecording` for disabled state.

- [ ] **Step 4: Build and commit**

Run: `swift test --filter AppStateRecordingTests`

Run: `swift build`

```bash
git add Tests/ClickerTests/AppStateRecordingTests.swift Sources/Clicker/App/AppState.swift Sources/Clicker/UI/ScriptListView.swift
git diff --cached --check
git commit -m "feat: expose recording from an empty library"
```

---

### Task 5: Surface Carbon Hot Key Registration Failures

**Files:**
- Create: `Tests/ClickerTests/HotKeyCenterTests.swift`
- Modify: `Sources/Clicker/App/HotKeyCenter.swift`
- Modify: `Sources/Clicker/App/AppState.swift`
- Modify: `Sources/Clicker/UI/MainView.swift`
- Modify: `Sources/Clicker/App/ClickerApp.swift`

**Interfaces:**
- Consumes: the exact imported `RegisterEventHotKey` function shape and both fixed record/play registrations.
- Produces: `HotKeyRegistrationIssue` with shortcut identity and `OSStatus`; `HotKeyCenter.register() -> [HotKeyRegistrationIssue]`; `AppState.hotKeyRegistrationIssue` for alert presentation.

- [ ] **Step 1: Write failing injected registration tests**

Inject a closure that returns `noErr` for record and `eventHotKeyExistsErr` for play. Assert one issue identifies the play shortcut and carries the literal status. Add the inverse failure and all-success cases. The injected closure must not call Carbon or install global hotkeys.

- [ ] **Step 2: Run the hot key tests and verify RED**

Run: `swift test --filter HotKeyCenterTests`

Expected: compilation failure because registration injection and structured issues are missing.

- [ ] **Step 3: Implement status checking and verify GREEN**

Factor the two registration descriptors through an internal injectable function. Append a hot-key ref only when status is `noErr`; convert every non-`noErr` result to `HotKeyRegistrationIssue`. Keep the existing event handler and notification routing unchanged.

Run: `swift test --filter HotKeyCenterTests`

- [ ] **Step 4: Publish and present startup failure**

Assign the first returned issue to `AppState.hotKeyRegistrationIssue` during app initialization. Add a `MainView` alert naming the unavailable shortcut and numeric `OSStatus`; do not hide persistence alerts or request new permissions.

- [ ] **Step 5: Verify and commit**

Run: `swift test --filter HotKeyCenterTests`

Run: `swift build`

```bash
git add Tests/ClickerTests/HotKeyCenterTests.swift Sources/Clicker/App/HotKeyCenter.swift Sources/Clicker/App/AppState.swift Sources/Clicker/UI/MainView.swift Sources/Clicker/App/ClickerApp.swift
git diff --cached --check
git commit -m "fix: report global hot key registration failures"
```

---

### Task 6: Enforce the Single Main Window Scene

**Files:**
- Modify: `Sources/Clicker/App/ClickerApp.swift`

**Interfaces:**
- Consumes: the existing single `MainView` root and shared `AppState`.
- Produces: one SwiftUI `Window("Clicker", id: "main")` scene instead of an unbounded `WindowGroup`; no navigation or state changes.

- [ ] **Step 1: Confirm the evaluation against the approved product shape**

The application has one script-library workspace, one process-wide recorder/playback state, and no document model or secondary-window command. `WindowGroup` can create multiple roots sharing that state, so the minimal correct scene is a single `Window`.

- [ ] **Step 2: Apply the one-scene change and compile it**

Replace only the scene declaration; retain `MainView`, environment injection, and minimum frame. This is declarative SwiftUI composition with no separately invocable production logic; its executable verification is compilation.

Run: `swift build`

Expected: the Clicker executable compiles for macOS 14 with the single-window scene.

- [ ] **Step 3: Commit the isolated scene adjustment**

```bash
git add Sources/Clicker/App/ClickerApp.swift
git diff --cached --check
git commit -m "fix: use a single main application window"
```

---

### Task 7: Full Verification and Sequential Review

**Files:**
- Review: every file changed in Tasks 1-6

**Interfaces:**
- Consumes: the complete Task 19B diff.
- Produces: passing tests/build, clean whitespace, files below 800 lines, and no tracked `.omc/` or handoff file.

- [ ] **Step 1: Run full automated verification**

```bash
swift test
swift build
git diff --check
find Sources Tests -name '*.swift' -print0 | xargs -0 wc -l | sort -nr | head -20
git status --short --branch
```

Expected: all tests pass, build succeeds, diff check has no output, every Swift file is below 800 lines, and status contains no unexpected file.

- [ ] **Step 2: Perform spec coverage review**

Trace each handoff bullet to a test and implementation: click release coordinates, shortcut release flags, scroll sampling, finite durations, one-point drag release, immutable reconstruction, playback edit freeze/snapshot, empty-library recording, Carbon status alert, and single-window decision.

- [ ] **Step 3: Perform code quality review**

Inspect metadata preservation, non-finite arithmetic, empty and one-point arrays, ordinal overflow, stale block identity, Carbon ref lifetime, multiple alerts, and all mutation entry points. Any discovered behavior bug begins a new RED/GREEN cycle before being fixed.

- [ ] **Step 4: Re-run evidence after review fixes**

Repeat the full commands from Step 1 and record test count, build result, largest Swift file, `git diff --check`, recent commits, and final status.

---

## Plan Self-Review

- Spec coverage: all ten Task 19B bullets map to Tasks 1-6 and the final review checklist.
- Placeholder scan: no deferred implementation markers or unspecified error-handling steps remain.
- Type consistency: Task 1 produces the pure functions Task 2 consumes; Task 3 produces edit policies Tasks 3-4 UI consumes; Task 5 registration issues flow from Carbon boundary through `AppState` to `MainView`.
- Test integrity: expectations are literal and hand-derived; system input, real global hotkeys, TCC, filesystem identity, and network are not touched by focused tests.
