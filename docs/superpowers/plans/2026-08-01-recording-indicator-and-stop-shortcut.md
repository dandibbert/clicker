# Recording Indicator and Stop Shortcut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a non-interactive red breathing recording indicator on every display and let users persist a single-key or modified-key recording stop shortcut from the main window.

**Architecture:** A value-type shortcut model and UserDefaults-backed store provide one immutable shortcut snapshot per recording. AppState passes that snapshot to both EventRecorder and a new AppKit recording-indicator presenter, while a focused SwiftUI settings sheet edits only future recordings.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, CoreGraphics, Swift Package Manager, XCTest, macOS 14+

## Global Constraints

- Strict TDD: run each target test and observe the expected failure before production edits.
- Do not post real keyboard or mouse input from tests.
- Do not modify TCC, `.netrc`, or Git identity and do not perform remote Git operations.
- Keep `.omc/` and `docs/superpowers/clicker-handoff.md` untracked.
- Stage exact task files only; never use `git add -A`.
- Every Swift file must remain below 800 lines.
- Use no third-party dependencies.
- The default recording stop shortcut remains Esc.
- All displays show the red border; only the main display shows the stop hint.
- Shortcut changes apply to the next recording, not an active recording.

---

### Task 1: Recording Stop Shortcut Model and Persistence

**Files:**
- Create: `Sources/Clicker/Recording/RecordingStopShortcut.swift`
- Create: `Tests/ClickerTests/RecordingStopShortcutTests.swift`

**Interfaces:**
- Produces: `struct RecordingStopShortcut: Codable, Equatable, Sendable`
- Produces: `static let defaultValue`, `static let supportedModifierMask`, `var displayName: String`
- Produces: `func matches(keyCode: UInt16, flags: UInt64) -> Bool`
- Produces: `enum Validation { case valid, riskyTextKey, conflict(String), modifierOnly }`
- Produces: `func validation(globalRecord: RecordingStopShortcut, globalPlay: RecordingStopShortcut) -> Validation`
- Produces: `final class RecordingStopShortcutStore` with `var shortcut: RecordingStopShortcut { get set }`

- [ ] **Step 1: Write failing model tests**

Add tests that express the public behavior before the types exist:

```swift
func testDefaultIsEscapeAndDisplaysEsc() {
    XCTAssertEqual(RecordingStopShortcut.defaultValue.keyCode, 53)
    XCTAssertEqual(RecordingStopShortcut.defaultValue.modifierFlags, 0)
    XCTAssertEqual(RecordingStopShortcut.defaultValue.displayName, "Esc")
}

func testMatchingIgnoresUnsupportedFlagsButRequiresConfiguredModifiers() {
    let shortcut = RecordingStopShortcut(keyCode: 1, modifierFlags: KeyCodeMap.maskOption)
    XCTAssertTrue(shortcut.matches(keyCode: 1, flags: KeyCodeMap.maskOption | (1 << 16)))
    XCTAssertFalse(shortcut.matches(keyCode: 1, flags: 0))
}

func testValidationRejectsGlobalConflictsAndFlagsPlainTextKeysAsRisky() {
    let record = RecordingStopShortcut(keyCode: 15, modifierFlags: KeyCodeMap.maskOption | KeyCodeMap.maskCommand)
    let play = RecordingStopShortcut(keyCode: 35, modifierFlags: KeyCodeMap.maskOption | KeyCodeMap.maskCommand)
    XCTAssertEqual(record.validation(globalRecord: record, globalPlay: play), .conflict("开始/停止录制"))
    XCTAssertEqual(RecordingStopShortcut(keyCode: 0, modifierFlags: 0).validation(globalRecord: record, globalPlay: play), .riskyTextKey)
}
```

- [ ] **Step 2: Run the model tests and verify RED**

Run: `swift test --filter RecordingStopShortcutTests`

Expected: compile failure because `RecordingStopShortcut` does not exist.

- [ ] **Step 3: Implement the minimal value model**

Implement modifier normalization with `KeyCodeMap.maskControl | maskOption | maskShift | maskCommand`, use `KeyCodeMap.shortcutDisplay`, classify key codes 0...50 that map to letters, digits, punctuation, Space, Return, and Tab as risky when no supported modifier is present, and compare exact normalized modifiers for matching and conflicts.

- [ ] **Step 4: Run model tests and verify GREEN**

Run: `swift test --filter RecordingStopShortcutTests`

Expected: all model tests pass with no compiler warnings.

- [ ] **Step 5: Add failing UserDefaults tests**

Use an isolated suite and assert round-trip plus fallback:

```swift
func testStoreRoundTripsShortcutAndFallsBackFromInvalidData() {
    let defaults = UserDefaults(suiteName: "Clicker-StopShortcut-\(UUID())")!
    let store = RecordingStopShortcutStore(defaults: defaults)
    let custom = RecordingStopShortcut(keyCode: 100, modifierFlags: KeyCodeMap.maskControl)
    store.shortcut = custom
    XCTAssertEqual(RecordingStopShortcutStore(defaults: defaults).shortcut, custom)
    defaults.set(Data("invalid".utf8), forKey: RecordingStopShortcutStore.storageKey)
    XCTAssertEqual(RecordingStopShortcutStore(defaults: defaults).shortcut, .defaultValue)
}
```

- [ ] **Step 6: Run persistence test and verify RED**

Run: `swift test --filter RecordingStopShortcutTests/testStoreRoundTripsShortcutAndFallsBackFromInvalidData`

Expected: compile failure because `RecordingStopShortcutStore` does not exist.

- [ ] **Step 7: Implement JSON-backed storage**

Implement `RecordingStopShortcutStore(defaults: UserDefaults = .standard)` using a namespaced data key. Decode on get, validate the decoded key as a non-modifier key, and return `.defaultValue` for missing or invalid data. Encode on set; if encoding unexpectedly fails, preserve the previous value.

- [ ] **Step 8: Run Task 1 tests and commit**

Run: `swift test --filter RecordingStopShortcutTests`

Then:

```bash
git add -- Sources/Clicker/Recording/RecordingStopShortcut.swift Tests/ClickerTests/RecordingStopShortcutTests.swift
git commit -m "feat: add recording stop shortcut settings"
```

---

### Task 2: EventRecorder Custom Stop Gesture

**Files:**
- Modify: `Sources/Clicker/Recording/RecordingDependencies.swift`
- Modify: `Sources/Clicker/Recording/EventRecorder.swift`
- Modify: `Sources/Clicker/App/AppState.swift`
- Modify: `Tests/ClickerTests/EventRecorderTests.swift`
- Modify: `Tests/ClickerTests/AppStateRecordingTests.swift`

**Interfaces:**
- Consumes: `RecordingStopShortcut`
- Changes: `EventRecording.start(stopShortcut: RecordingStopShortcut) -> Bool`
- Produces: one stop request per matching physical gesture while filtering its down/repeat/up events

- [ ] **Step 1: Write failing recorder tests**

Replace hard-coded Escape assumptions with explicit snapshots and add combination coverage:

```swift
func testCustomCombinationRequiresExactSupportedModifiersAndIsNotRecorded() async throws {
    let tap = StubEventTapSession()
    let recorder = EventRecorder(eventTap: tap)
    let requested = expectation(description: "custom shortcut requests stop")
    requested.assertForOverFulfill = true
    recorder.onStopRequest = { requested.fulfill() }
    let shortcut = RecordingStopShortcut(keyCode: 1, modifierFlags: KeyCodeMap.maskOption | KeyCodeMap.maskCommand)
    XCTAssertTrue(recorder.start(stopShortcut: shortcut))

    tap.emit(type: .keyDown, event: try keyEvent(keyCode: 1, flags: [.maskAlternate]))
    tap.emit(type: .keyDown, event: try keyEvent(keyCode: 1, flags: [.maskAlternate, .maskCommand]))
    tap.emit(type: .keyUp, event: try keyEvent(keyCode: 1, keyDown: false, flags: [.maskAlternate, .maskCommand]))

    await fulfillment(of: [requested], timeout: 1)
    XCTAssertEqual(recorder.stop().events.count, 1)
}
```

Also assert repeated matching keyDown calls `onStopRequest` once and that default Esc still works.

- [ ] **Step 2: Run recorder tests and verify RED**

Run: `swift test --filter EventRecorderTests`

Expected: compile failure because `start(stopShortcut:)` is missing.

- [ ] **Step 3: Implement shortcut snapshot detection**

Store the snapshot only after event-tap startup succeeds. In `handle`, replace keyCode 53 with `stopShortcut.matches`. Latch on the first matching keyDown, ignore later events after the latch, and never append the matching control gesture. Clear the snapshot and latch on every new start.

- [ ] **Step 4: Update protocol and existing stubs**

Change every `EventRecording` implementation and test stub to:

```swift
func start(stopShortcut: RecordingStopShortcut) -> Bool
```

Temporarily pass `.defaultValue` from `AppState` so compilation is restored; Task 4 will replace this with the persisted snapshot.

- [ ] **Step 5: Run recorder and recording-state tests**

Run:

```bash
swift test --filter EventRecorderTests
swift test --filter AppStateRecordingTests
```

Expected: all selected tests pass.

- [ ] **Step 6: Commit Task 2**

```bash
git add -- Sources/Clicker/Recording/RecordingDependencies.swift Sources/Clicker/Recording/EventRecorder.swift Sources/Clicker/App/AppState.swift Tests/ClickerTests/EventRecorderTests.swift Tests/ClickerTests/AppStateRecordingTests.swift
git commit -m "feat: support custom recording stop gesture"
```

---

### Task 3: Multi-Display Recording Indicator

**Files:**
- Create: `Sources/Clicker/Recording/RecordingIndicatorController.swift`
- Create: `Sources/Clicker/UI/RecordingIndicatorView.swift`
- Create: `Tests/ClickerTests/RecordingIndicatorControllerTests.swift`
- Modify: `Sources/Clicker/Recording/RecordingDependencies.swift`

**Interfaces:**
- Produces: `protocol RecordingIndicatorPresenting: AnyObject { func show(shortcut: RecordingStopShortcut); func close() }`
- Produces: `@MainActor final class RecordingIndicatorController: RecordingIndicatorPresenting`
- Produces: injectable screen descriptors and panel factory so tests do not depend on the user's physical displays

- [ ] **Step 1: Write failing presenter lifecycle tests**

Express one panel per screen, main-only hint, and idempotent cleanup through injected factories:

```swift
func testShowCreatesOneNonInteractivePanelPerScreenAndMainScreenGetsHint() {
    let screens = [ScreenDescriptor(id: "main", frame: mainFrame, isMain: true), ScreenDescriptor(id: "side", frame: sideFrame, isMain: false)]
    let panels = PanelSpy.factory()
    let controller = RecordingIndicatorController(screens: { screens }, makePanel: panels.make)
    controller.show(shortcut: .defaultValue)
    XCTAssertEqual(panels.created.map(\.descriptor.id), ["main", "side"])
    XCTAssertEqual(panels.created.map(\.showsHint), [true, false])
    XCTAssertTrue(panels.created.allSatisfy { $0.ignoresMouseEvents && !$0.becomesKey })
}

func testCloseOrdersOutEveryPanelOnceAndCanRepeat() {
    // Show two panels, call close twice, assert one close per panel and no retained panels.
}
```

- [ ] **Step 2: Run indicator tests and verify RED**

Run: `swift test --filter RecordingIndicatorControllerTests`

Expected: compile failure because the presenter/controller types do not exist.

- [ ] **Step 3: Implement the controller and panel configuration**

The production screen provider maps `NSScreen.screens`; main identity comes from `NSScreen.main`. Configure each `NSPanel` with `.borderless`, `.nonactivatingPanel`, `level = .screenSaver`, `hidesOnDeactivate = false`, `ignoresMouseEvents = true`, clear background, and collection behavior containing `.canJoinAllSpaces`, `.fullScreenAuxiliary`, and `.stationary`. Call `orderFrontRegardless()` and never activate Clicker.

- [ ] **Step 4: Implement the SwiftUI visual**

`RecordingIndicatorView` fills the screen with a clear hit-test-disabled layer, an inset rounded red stroke, and a repeating opacity animation. When `showsHint` is true, place a dark material capsule near the top containing `正在录制 · 按 \(shortcut.displayName) 停止`. Keep this file presentation-only.

- [ ] **Step 5: Run indicator tests and verify GREEN**

Run: `swift test --filter RecordingIndicatorControllerTests`

Expected: all selected tests pass without showing persistent test windows.

- [ ] **Step 6: Commit Task 3**

```bash
git add -- Sources/Clicker/Recording/RecordingIndicatorController.swift Sources/Clicker/UI/RecordingIndicatorView.swift Sources/Clicker/Recording/RecordingDependencies.swift Tests/ClickerTests/RecordingIndicatorControllerTests.swift
git commit -m "feat: add multi-display recording indicator"
```

---

### Task 4: AppState Snapshot and Indicator Lifecycle

**Files:**
- Modify: `Sources/Clicker/App/AppState.swift`
- Modify: `Sources/Clicker/Recording/RecordingDependencies.swift`
- Modify: `Tests/ClickerTests/AppStateRecordingTests.swift`

**Interfaces:**
- Consumes: `RecordingStopShortcutStore`, `RecordingIndicatorPresenting`
- Changes AppState initializer to inject `stopShortcutStore` and `recordingIndicator`
- Guarantees the same immutable shortcut value reaches recorder and indicator

- [ ] **Step 1: Write failing AppState tests**

Extend the recorder stub to collect `startShortcuts` and add an indicator spy:

```swift
func testSuccessfulRecorderStartShowsIndicatorWithSamePersistedShortcut() async {
    let custom = RecordingStopShortcut(keyCode: 100, modifierFlags: KeyCodeMap.maskControl)
    let store = StubStopShortcutStore(shortcut: custom)
    let recorder = StubEventRecorder(startResult: true)
    let indicator = StubRecordingIndicator()
    let state = makeState(recorder: recorder, countdown: ImmediateCountdown(), stopStore: store, indicator: indicator)
    state.hasPermission = true
    state.toggleRecord(source: .ui)
    await Task.yield()
    XCTAssertEqual(recorder.startShortcuts, [custom])
    XCTAssertEqual(indicator.shownShortcuts, [custom])
}
```

Add separate tests asserting no show on start failure/countdown cancellation and close on UI stop, menu stop, stop request, and tap failure.

- [ ] **Step 2: Run AppState tests and verify RED**

Run: `swift test --filter AppStateRecordingTests`

Expected: compile failure because AppState does not accept stop-store or indicator dependencies.

- [ ] **Step 3: Add a store protocol and production dependency defaults**

Add:

```swift
protocol RecordingStopShortcutProviding: AnyObject {
    var shortcut: RecordingStopShortcut { get set }
}
```

Make `RecordingStopShortcutStore` conform. Default AppState dependencies are the production store and `RecordingIndicatorController()`.

- [ ] **Step 4: Implement one-snapshot lifecycle**

Read and retain `activeStopShortcut` before countdown. Pass it to recorder on finish. Only after a successful start call `recordingIndicator.show(shortcut:)`. Call `recordingIndicator.close()` at the beginning of every terminal recording path and clear `activeStopShortcut`; countdown cancellation closes defensively without ever showing.

- [ ] **Step 5: Run AppState and recorder tests**

Run:

```bash
swift test --filter AppStateRecordingTests
swift test --filter EventRecorderTests
```

Expected: all selected tests pass.

- [ ] **Step 6: Commit Task 4**

```bash
git add -- Sources/Clicker/App/AppState.swift Sources/Clicker/Recording/RecordingDependencies.swift Tests/ClickerTests/AppStateRecordingTests.swift
git commit -m "feat: connect recording indicator lifecycle"
```

---

### Task 5: Main-Window Recording Settings Sheet

**Files:**
- Create: `Sources/Clicker/UI/RecordingSettingsView.swift`
- Create: `Sources/Clicker/UI/ShortcutCaptureView.swift`
- Create: `Tests/ClickerTests/ShortcutCaptureTests.swift`
- Modify: `Sources/Clicker/App/AppState.swift`
- Modify: `Sources/Clicker/UI/MainView.swift`

**Interfaces:**
- Produces: `ShortcutCaptureController` with `func candidate(keyCode: UInt16, flags: UInt64) -> RecordingStopShortcut?`
- Produces: `RecordingSettingsView` bound to AppState's persisted `recordingStopShortcut`
- Adds toolbar action that is enabled only for `.idle`

- [ ] **Step 1: Write failing capture-controller tests**

Test the event-independent controller rather than posting system input:

```swift
func testModifierOnlyKeyDoesNotProduceCandidate() {
    XCTAssertNil(ShortcutCaptureController().candidate(keyCode: 55, flags: KeyCodeMap.maskCommand))
}

func testCandidateNormalizesModifiers() {
    let candidate = ShortcutCaptureController().candidate(keyCode: 1, flags: KeyCodeMap.maskOption | (1 << 16))
    XCTAssertEqual(candidate, RecordingStopShortcut(keyCode: 1, modifierFlags: KeyCodeMap.maskOption))
}
```

- [ ] **Step 2: Run capture tests and verify RED**

Run: `swift test --filter ShortcutCaptureTests`

Expected: compile failure because `ShortcutCaptureController` does not exist.

- [ ] **Step 3: Implement capture controller and local key view**

Implement the pure controller first. `ShortcutCaptureView` wraps a focusable `NSView` whose `keyDown(with:)` converts `event.keyCode` and `event.modifierFlags.rawValue` through the controller and returns candidates via a closure. It must not install global monitors or post input.

- [ ] **Step 4: Run capture tests and verify GREEN**

Run: `swift test --filter ShortcutCaptureTests`

Expected: selected tests pass.

- [ ] **Step 5: Add AppState setting access and the SwiftUI sheet**

Expose a main-actor `recordingStopShortcut` getter/setter backed by the injected store. Build a sheet that shows the current display name, toggles capture mode, validates candidates against `⌥⌘R` and `⌥⌘P`, preserves the old value on conflict, shows the plain-text-key warning, and restores `.defaultValue`. Disable entry whenever `phase != .idle`.

- [ ] **Step 6: Add the toolbar button**

In `MainView`, add an always-discoverable gear/recording-settings toolbar item so it remains available even when the script library is empty. Present `RecordingSettingsView` via sheet, disable the button outside `.idle`, and dismiss the sheet if the phase leaves `.idle`.

- [ ] **Step 7: Run focused UI-model and state tests**

Run:

```bash
swift test --filter ShortcutCaptureTests
swift test --filter RecordingStopShortcutTests
swift test --filter AppStateRecordingTests
```

Expected: all selected tests pass.

- [ ] **Step 8: Commit Task 5**

```bash
git add -- Sources/Clicker/UI/RecordingSettingsView.swift Sources/Clicker/UI/ShortcutCaptureView.swift Sources/Clicker/App/AppState.swift Sources/Clicker/UI/MainView.swift Tests/ClickerTests/ShortcutCaptureTests.swift
git commit -m "feat: add recording stop shortcut UI"
```

---

### Task 6: Full Verification, Review, and Bundle

**Files:**
- Modify only files required by review findings, with a new failing regression test before each production correction.
- Rebuild: `dist/Clicker.app` through the existing script.

**Interfaces:**
- Verifies the complete feature and preserves the existing recording/playback invariants.

- [ ] **Step 1: Run the complete test and build gates**

Run:

```bash
swift test
swift build
git diff --check
find Sources Tests -name '*.swift' -print0 | xargs -0 wc -l | sort -nr | head -n 20
```

Expected: zero test failures, both commands exit 0, no whitespace errors, no Swift file reaches 800 lines.

- [ ] **Step 2: Perform spec and code-quality review**

Review the implementation against every requirement in `docs/superpowers/specs/2026-08-01-recording-indicator-and-stop-shortcut-design.md`. Report only concrete Critical/Important findings. Stop the reviewer immediately after it returns or after 60 seconds without response.

- [ ] **Step 3: Remediate findings through fresh TDD cycles**

For each accepted finding: add and run one failing regression test, implement the smallest production fix, rerun the focused test, then rerun the full suite. Do not bundle unrelated cleanup.

- [ ] **Step 4: Build and validate the app bundle**

Run:

```bash
./scripts/build-app.sh
plutil -lint dist/Clicker.app/Contents/Info.plist
codesign --verify --deep --strict --verbose=2 dist/Clicker.app
stat -f 'mtime=%Sm size=%z path=%N' -t '%Y-%m-%d %H:%M:%S %z' dist/Clicker.app/Contents/MacOS/Clicker
shasum -a 256 dist/Clicker.app/Contents/MacOS/Clicker
```

Expected: release build succeeds, plist and signature validate, and the binary has a fresh timestamp/hash.

- [ ] **Step 5: Record the manual verification handoff**

Ask the user to verify: full 3-2-1 countdown; red breathing border on every display; hint only on main display; configured shortcut stops and restores Clicker; Esc works after restoring defaults; conflicting shortcuts are rejected; no invisible window intercepts mouse input.

- [ ] **Step 6: Commit any final review-only corrections and report Git evidence**

Stage only the exact corrected files, use a Conventional Commit describing the correction, and finish with:

```bash
git status --short --branch
git log -6 --oneline --decorate
```

Expected: only `.omc/` and `docs/superpowers/clicker-handoff.md` remain untracked.
