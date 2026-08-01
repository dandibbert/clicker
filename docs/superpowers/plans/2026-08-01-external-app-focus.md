# External Application Focus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hide Clicker and activate the correct external application before recording or playback, then restore Clicker exactly once when the active session ends.

**Architecture:** A process-lifetime `SystemExternalApplicationTracker` records only valid non-Clicker bundle identifiers and is started by `ApplicationServiceCoordinator`. `AppState` snapshots that tracker, while one shared `SystemApplicationController` owns Clicker window conceal/reveal and best-effort activation of already-running external applications; `PlaybackEngine` remains responsible only for timed input delivery.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit (`NSWorkspace`, `NSRunningApplication`, `NSApplication`), XCTest, Swift Package Manager, macOS 14+.

## Global Constraints

- Strict TDD: run the focused failing test and record its RED result before changing production code.
- Do not send real keyboard or mouse input from automated tests.
- Do not switch real applications from automated tests; inject notification, bundle-identifier, activation, and window closures.
- Do not modify TCC, `.netrc`, or Git identity.
- Do not perform any remote Git operation.
- Keep `.omc/` and `docs/superpowers/clicker-handoff.md` untracked and never stage them.
- Stage exact task files only; never use `git add -A` or `git add .`.
- Use Conventional Commits.
- Swift 5.9, SwiftUI, AppKit, macOS 14+.
- Do not add third-party dependencies.
- Keep every Swift file below 800 lines.
- Do not automatically launch an application that is not already running.
- After every task, report focused test, build, and `git status --short --branch` evidence.
- Stop any completed, failed, or unresponsive agent immediately; avoid unnecessary parallel agents.

---

## File Structure

- Create `Sources/Clicker/App/ExternalApplicationTracker.swift`: filtering, initial snapshot, workspace activation observation, and idempotent start.
- Create `Sources/Clicker/App/ApplicationController.swift`: shared external activation plus Clicker conceal, deactivate, reveal, and activate behavior.
- Modify `Sources/Clicker/App/AppState.swift`: snapshot targets and centrally own recording/playback focus lifecycle and generation-safe restoration.
- Modify `Sources/Clicker/App/ApplicationServiceCoordinator.swift`: start and retain the tracker once with other process-level services.
- Modify `Sources/Clicker/App/ClickerApp.swift`: use the state-owned tracker through the coordinator.
- Modify `Sources/Clicker/Recording/RecordingDependencies.swift`: remove frontmost-app lookup and the old recording-only controller; retain recording protocols.
- Modify `Sources/Clicker/Playback/PlaybackEngine.swift`: remove application capture/restore responsibility.
- Delete `Sources/Clicker/Playback/PlaybackApplicationController.swift` in Task 5 after `PlaybackEngine` no longer references it.
- Create `Tests/ClickerTests/ExternalApplicationTrackerTests.swift`: deterministic tracker behavior tests.
- Create `Tests/ClickerTests/ApplicationControllerTests.swift`: deterministic activation and Clicker window lifecycle tests.
- Modify `Tests/ClickerTests/AppStateRecordingTests.swift`: recording target snapshots, ordering, failure, cancellation, and restore coverage.
- Modify `Tests/ClickerTests/AppStatePlaybackTests.swift`: saved-target priority, fallback, ordering, and exactly-once restore coverage.
- Modify `Tests/ClickerTests/ApplicationServicesTests.swift`: tracker service startup and idempotence coverage.
- Modify `Tests/ClickerTests/PlaybackEngineTests.swift`: prove playback no longer activates or restores applications.
- Delete `Tests/ClickerTests/RecordingApplicationControllerTests.swift` in Task 2 and `Tests/ClickerTests/PlaybackApplicationControllerTests.swift` in Task 5 after their respective replacements are in place.

### Task 1: Track the Most Recent External Application

**Files:**
- Create: `Sources/Clicker/App/ExternalApplicationTracker.swift`
- Create: `Tests/ClickerTests/ExternalApplicationTrackerTests.swift`

**Interfaces:**
- Produces: `protocol ExternalApplicationTracking: AnyObject { var mostRecentExternalBundleIdentifier: String? { get }; func start() }`
- Produces: `final class SystemExternalApplicationTracker: ExternalApplicationTracking`
- Constructor for tests: `init(clickerBundleIdentifier: String = "local.rayscripts.clicker", initialFrontmostBundleIdentifier: @escaping () -> String?, notificationCenter: NotificationCenter = .default, activatedBundleIdentifier: @escaping (Notification) -> String?)`
- Invariant: empty identifiers and `local.rayscripts.clicker` never overwrite the last valid external identifier.

- [ ] **Step 1: Write tracker behavior tests**

Create tests equivalent to:

```swift
func testStartCapturesInitialExternalApplicationAndIsIdempotent() {
    let center = NotificationCenter()
    var initialReads = 0
    let tracker = SystemExternalApplicationTracker(
        initialFrontmostBundleIdentifier: {
            initialReads += 1
            return "com.example.editor"
        },
        notificationCenter: center,
        activatedBundleIdentifier: { $0.object as? String }
    )

    tracker.start()
    tracker.start()

    XCTAssertEqual(tracker.mostRecentExternalBundleIdentifier, "com.example.editor")
    XCTAssertEqual(initialReads, 1)
}

func testNotificationsIgnoreClickerAndEmptyIdentifiersButAcceptExternalApplication() {
    let center = NotificationCenter()
    let tracker = SystemExternalApplicationTracker(
        initialFrontmostBundleIdentifier: { "com.example.first" },
        notificationCenter: center,
        activatedBundleIdentifier: { $0.object as? String }
    )
    tracker.start()

    center.post(name: NSWorkspace.didActivateApplicationNotification, object: "")
    center.post(name: NSWorkspace.didActivateApplicationNotification, object: "local.rayscripts.clicker")
    XCTAssertEqual(tracker.mostRecentExternalBundleIdentifier, "com.example.first")

    center.post(name: NSWorkspace.didActivateApplicationNotification, object: "com.example.second")
    XCTAssertEqual(tracker.mostRecentExternalBundleIdentifier, "com.example.second")
}
```

Also cover an initial `nil`, empty, and Clicker identifier, and prove Clicker reactivation preserves a previously recorded external identifier.

- [ ] **Step 2: Run the focused tests and capture RED**

Run: `swift test --filter ExternalApplicationTrackerTests`

Expected: FAIL to compile because `SystemExternalApplicationTracker` does not exist.

- [ ] **Step 3: Implement the minimal tracker**

Implement the protocol and tracker with these production defaults:

```swift
protocol ExternalApplicationTracking: AnyObject {
    var mostRecentExternalBundleIdentifier: String? { get }
    func start()
}

final class SystemExternalApplicationTracker: ExternalApplicationTracking {
    private(set) var mostRecentExternalBundleIdentifier: String?
    private var observer: NSObjectProtocol?
    private var hasStarted = false

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        accept(initialFrontmostBundleIdentifier())
        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.accept(activatedBundleIdentifier(notification))
        }
    }

    private func accept(_ candidate: String?) {
        guard let candidate, !candidate.isEmpty,
              candidate != clickerBundleIdentifier else { return }
        mostRecentExternalBundleIdentifier = candidate
    }
}
```

The no-argument production initializer must read `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` and extract `NSWorkspace.applicationUserInfoKey` as `NSRunningApplication` from activation notifications. Remove the observer in `deinit`.

- [ ] **Step 4: Run focused tests and build**

Run: `swift test --filter ExternalApplicationTrackerTests && swift build`

Expected: all tracker tests PASS and Debug build succeeds.

- [ ] **Step 5: Verify file sizes and repository state**

Run: `wc -l Sources/Clicker/App/ExternalApplicationTracker.swift Tests/ClickerTests/ExternalApplicationTrackerTests.swift && git diff --check && git status --short --branch`

Expected: each Swift file is below 800 lines; only the two task files plus the two required untracked paths are present.

- [ ] **Step 6: Commit the tracker**

```bash
git add Sources/Clicker/App/ExternalApplicationTracker.swift Tests/ClickerTests/ExternalApplicationTrackerTests.swift
git commit -m "feat: track recent external application"
```

### Task 2: Share Window and External Activation Control

**Files:**
- Create: `Sources/Clicker/App/ApplicationController.swift`
- Create: `Tests/ClickerTests/ApplicationControllerTests.swift`
- Modify: `Sources/Clicker/App/AppState.swift`
- Modify: `Sources/Clicker/Recording/RecordingDependencies.swift`
- Modify: `Tests/ClickerTests/AppStateRecordingTests.swift`
- Modify: `Tests/ClickerTests/AppStatePlaybackTests.swift`
- Delete: `Tests/ClickerTests/RecordingApplicationControllerTests.swift`

**Interfaces:**
- Produces: `@MainActor protocol ApplicationControlling: AnyObject`
- Required methods: `func frontmostApplicationBundleIdentifier() -> String?`, `func activateExternalApplication(bundleIdentifier: String) -> Bool`, `func hideClicker()`, and `func restoreClicker()`. The frontmost lookup remains only as a compile-compatible bridge until Task 4 replaces its final `AppState` caller with the tracker snapshot and then removes it from the protocol/controller.
- Produces: `@MainActor final class SystemApplicationController: ApplicationControlling`.
- Consumes later: `AppState` calls activation only after `hideClicker()`; activation failure does not undo deactivation.

- [ ] **Step 1: Write shared controller tests**

Test injected closures without real application activation:

```swift
func testActivationDelegatesOnlyToRequestedRunningBundleIdentifier() {
    var identifiers: [String] = []
    let controller = SystemApplicationController(
        visibleWindows: { [] }, conceal: { _ in }, reveal: { _ in },
        deactivateClicker: {}, activateClicker: {},
        activateExternal: { identifiers.append($0); return $0 == "com.example.target" }
    )

    XCTAssertTrue(controller.activateExternalApplication(bundleIdentifier: "com.example.target"))
    XCTAssertFalse(controller.activateExternalApplication(bundleIdentifier: "com.example.missing"))
    XCTAssertEqual(identifiers, ["com.example.target", "com.example.missing"])
}
```

Port the existing conceal/reveal test and hidden-window lifecycle test to `SystemApplicationController`. Add a test that an activation failure leaves the already-hidden Clicker deactivated and concealed until `restoreClicker()`.

- [ ] **Step 2: Run the focused tests and capture RED**

Run: `swift test --filter ApplicationControllerTests`

Expected: FAIL to compile because `SystemApplicationController` and `ApplicationControlling` do not exist.

- [ ] **Step 3: Implement the shared controller and remove obsolete controllers**

Move window logic out of `RecordingDependencies.swift` and implement:

```swift
@MainActor
protocol ApplicationControlling: AnyObject {
    func frontmostApplicationBundleIdentifier() -> String?
    func activateExternalApplication(bundleIdentifier: String) -> Bool
    func hideClicker()
    func restoreClicker()
}

func activateExternalApplication(bundleIdentifier: String) -> Bool {
    activateExternal(bundleIdentifier)
}
```

The production `activateExternal` closure must call `NSRunningApplication.runningApplications(withBundleIdentifier:)`, return `false` when no process is running, and otherwise call `activate(options: [.activateAllWindows])`. Preserve the existing window filtering (`isVisible && !(window is NSPanel)`), alpha/mouse behavior, `NSApp.deactivate()`, and `NSApp.activate(ignoringOtherApps: true)`. Keep the old playback session types temporarily because `PlaybackEngine` still consumes them until Task 5.

- [ ] **Step 4: Update test-only references to the renamed protocol enough to compile**

Replace `RecordingApplicationControlling` conformances with `ApplicationControlling`. Preserve each stub's deterministic `frontmostApplicationBundleIdentifier()` until Task 4, and add a deterministic `activateExternalApplication` stub method that records the identifier and returns a configurable result. Change the `AppState` initializer default from `SystemRecordingApplicationController()` to `SystemApplicationController()`, but do not change recording behavior in this task.

- [ ] **Step 5: Run focused controller tests, existing app-state tests, and build**

Run: `swift test --filter ApplicationControllerTests && swift test --filter AppState && swift build`

Expected: shared controller and existing AppState tests PASS; Debug build succeeds.

- [ ] **Step 6: Verify deletions, sizes, diff, and Git state**

Run: `test ! -e Tests/ClickerTests/RecordingApplicationControllerTests.swift && wc -l Sources/Clicker/App/ApplicationController.swift Tests/ClickerTests/ApplicationControllerTests.swift Sources/Clicker/Recording/RecordingDependencies.swift && git diff --check && git status --short --branch`

Expected: deleted files are absent, Swift files are below 800 lines, and only task files plus required untracked paths are changed.

- [ ] **Step 7: Commit the shared controller**

```bash
git add Sources/Clicker/App/ApplicationController.swift Tests/ClickerTests/ApplicationControllerTests.swift Sources/Clicker/Recording/RecordingDependencies.swift Tests/ClickerTests/RecordingApplicationControllerTests.swift Tests/ClickerTests/AppStateRecordingTests.swift Tests/ClickerTests/AppStatePlaybackTests.swift
git commit -m "refactor: share application focus controller"
```

### Task 3: Integrate Tracker Startup with Application Services

**Files:**
- Modify: `Sources/Clicker/App/AppState.swift`
- Modify: `Sources/Clicker/App/ApplicationServiceCoordinator.swift`
- Modify: `Sources/Clicker/App/ClickerApp.swift`
- Modify: `Tests/ClickerTests/ApplicationServicesTests.swift`

**Interfaces:**
- Consumes: `ExternalApplicationTracking` from Task 1.
- Produces: internal `let externalApplicationTracker: ExternalApplicationTracking` on `AppState` for coordinator reuse.
- `ApplicationServiceCoordinator.start()` calls tracker `start()` in the same idempotent service startup gate.

- [ ] **Step 1: Add the failing service-start test**

Add a stub tracker and assert exact startup behavior:

```swift
final class StubExternalApplicationTracker: ExternalApplicationTracking {
    var mostRecentExternalBundleIdentifier: String?
    private(set) var startCallCount = 0
    func start() { startCallCount += 1 }
}

func testSystemServicesStartTrackerOnlyOnce() {
    let tracker = StubExternalApplicationTracker()
    let state = AppState(store: store, externalApplicationTracker: tracker)
    let services = ApplicationServiceCoordinator(
        state: state,
        makeStatusItem: { NSObject() },
        registerHotKeys: { [] }
    )

    services.start()
    services.start()

    XCTAssertEqual(tracker.startCallCount, 1)
}
```

- [ ] **Step 2: Run the focused test and capture RED**

Run: `swift test --filter ApplicationServicesTests/testSystemServicesStartTrackerOnlyOnce`

Expected: FAIL to compile because `AppState` does not accept or expose `externalApplicationTracker`.

- [ ] **Step 3: Add tracker ownership and startup**

Add this initializer dependency to `AppState`:

```swift
let externalApplicationTracker: ExternalApplicationTracking

init(
    // existing dependencies,
    externalApplicationTracker: ExternalApplicationTracking = SystemExternalApplicationTracker(),
    // remaining dependencies
) {
    self.externalApplicationTracker = externalApplicationTracker
}
```

In `ApplicationServiceCoordinator.start()`, call `state.externalApplicationTracker.start()` after the single-start guard. Keep `ClickerApp` constructing one `AppState` and one coordinator; do not create a second tracker in the SwiftUI entry point.

- [ ] **Step 4: Run service tests, full tests, and build**

Run: `swift test --filter ApplicationServicesTests && swift test && swift build`

Expected: service tests and full suite PASS; Debug build succeeds.

- [ ] **Step 5: Verify sizes, diff, and Git state**

Run: `wc -l Sources/Clicker/App/AppState.swift Sources/Clicker/App/ApplicationServiceCoordinator.swift Sources/Clicker/App/ClickerApp.swift Tests/ClickerTests/ApplicationServicesTests.swift && git diff --check && git status --short --branch`

Expected: every Swift file remains below 800 lines and only task files plus required untracked paths are changed.

- [ ] **Step 6: Commit tracker service wiring**

```bash
git add Sources/Clicker/App/AppState.swift Sources/Clicker/App/ApplicationServiceCoordinator.swift Sources/Clicker/App/ClickerApp.swift Tests/ClickerTests/ApplicationServicesTests.swift
git commit -m "feat: start external application tracking"
```

### Task 4: Apply Focus Lifecycle to Recording

**Files:**
- Modify: `Sources/Clicker/App/AppState.swift`
- Modify: `Sources/Clicker/App/ApplicationController.swift`
- Modify: `Tests/ClickerTests/AppStateRecordingTests.swift`
- Modify: `Tests/ClickerTests/AppStatePlaybackTests.swift`

**Interfaces:**
- Consumes: `externalApplicationTracker.mostRecentExternalBundleIdentifier` and `ApplicationControlling`.
- Recording start order: target snapshot, shortcut snapshot, countdown show, Clicker hide/deactivate, optional target activation.
- Recording completion contract: cancellation, recorder start failure, tap failure, stop request, menu-bar stop, and normal UI stop each restore Clicker once.

- [ ] **Step 1: Replace frontmost lookup assertions with tracker snapshot and activation tests**

Add deterministic stubs and assertions equivalent to:

```swift
func testRecordingSnapshotsTargetThenShowsHidesAndActivatesInOrder() {
    var calls: [String] = []
    let tracker = StubExternalApplicationTracker(
        mostRecentExternalBundleIdentifier: "com.example.target",
        onRead: { calls.append("targetSnapshot") }
    )
    let countdown = ControlledCountdown(onShow: { calls.append("showCountdown") })
    let application = StubApplicationController(onCall: { calls.append($0) })
    let state = makeState(countdown: countdown, application: application, tracker: tracker)
    state.hasPermission = true

    state.toggleRecord(source: .ui)

    XCTAssertEqual(calls, ["targetSnapshot", "showCountdown", "hide", "activate:com.example.target"])
}
```

Add cases for no recent target (hide/deactivate but no activation), failed activation (countdown proceeds), and tracker mutation during countdown (saved script still contains the original target). Retain assertions that cancellation, recorder-start failure, tap failure, UI stop, menu-bar stop, and stop shortcut each result in exactly one `restore` call.

- [ ] **Step 2: Run recording tests and capture RED**

Run: `swift test --filter AppStateRecordingTests`

Expected: FAIL because `AppState` still reads the old frontmost method and never activates the snapshot.

- [ ] **Step 3: Implement minimal recording focus behavior**

Change `startCountdown()` to follow this shape, then remove the now-unused `frontmostApplicationBundleIdentifier()` requirement and implementation from `ApplicationControlling`, `SystemApplicationController`, and test stubs:

```swift
let target = externalApplicationTracker.mostRecentExternalBundleIdentifier
recordingTargetBundleIdentifier = target
activeStopShortcut = stopShortcutStore.shortcut
phase = .countdown(3)
countdown.show(seconds: 3, onTick: ..., onFinish: ...)
application.hideClicker()
if let target {
    _ = application.activateExternalApplication(bundleIdentifier: target)
}
```

Do not reread the tracker in countdown callbacks. Keep every existing failure/cancellation path calling `restoreClicker()` after returning to `.idle`, and clear `recordingTargetBundleIdentifier` when cancellation or startup failure makes the snapshot obsolete.

- [ ] **Step 4: Run focused recording tests and build**

Run: `swift test --filter AppStateRecordingTests && swift build`

Expected: all recording tests PASS and Debug build succeeds.

- [ ] **Step 5: Verify sizes, diff, and Git state**

Run: `wc -l Sources/Clicker/App/AppState.swift Tests/ClickerTests/AppStateRecordingTests.swift && git diff --check && git status --short --branch`

Expected: both files remain below 800 lines and only task files plus required untracked paths are changed.

- [ ] **Step 6: Commit recording focus behavior**

```bash
git add Sources/Clicker/App/AppState.swift Sources/Clicker/App/ApplicationController.swift Tests/ClickerTests/AppStateRecordingTests.swift Tests/ClickerTests/AppStatePlaybackTests.swift
git commit -m "feat: focus recording target application"
```

### Task 5: Move Playback Focus Lifecycle into AppState

**Files:**
- Modify: `Sources/Clicker/App/AppState.swift`
- Modify: `Sources/Clicker/Playback/PlaybackEngine.swift`
- Delete: `Sources/Clicker/Playback/PlaybackApplicationController.swift`
- Modify: `Tests/ClickerTests/AppStatePlaybackTests.swift`
- Modify: `Tests/ClickerTests/PlaybackEngineTests.swift`
- Delete: `Tests/ClickerTests/PlaybackApplicationControllerTests.swift`

**Interfaces:**
- Consumes: script `targetBundleIdentifier`, tracker fallback snapshot, and `ApplicationControlling`.
- Activation algorithm: reject empty and Clicker identifiers; try saved target first; on failure try a distinct valid fallback; never block playback on activation failure.
- Restoration algorithm: one generation owns the hidden Clicker; natural finish or explicit stop invalidates that generation and restores once; late callbacks cannot affect a replacement session.
- `PlaybackEngine` produces input lifecycle only and has no application controller/session dependency.

- [ ] **Step 1: Add failing AppState playback focus tests**

Cover all target choices and call ordering:

```swift
func testPlaybackHidesAndActivatesSavedTargetBeforeStartingEngine() {
    let script = playableScript(targetBundleIdentifier: "com.example.saved")
    let context = makeContext(script: script, recentTarget: "com.example.recent")

    context.state.togglePlay()

    XCTAssertEqual(context.calls, ["hide", "activate:com.example.saved", "play"])
}

func testPlaybackFallsBackOnceWhenSavedTargetActivationFails() {
    let context = makeContext(
        script: playableScript(targetBundleIdentifier: "com.example.saved"),
        recentTarget: "com.example.recent",
        activationResults: ["com.example.saved": false, "com.example.recent": true]
    )

    context.state.togglePlay()

    XCTAssertEqual(context.application.activationAttempts,
                   ["com.example.saved", "com.example.recent"])
}
```

Also test missing/empty/Clicker saved target, identical saved and fallback target (one attempt), both attempts failing (engine still starts), and fallback snapshot stability.

- [ ] **Step 2: Add failing restoration race tests**

Assert `restoreClicker()` exactly once for natural completion, explicit stop, termination cleanup, and replacement. Preserve the existing late-finish test and additionally assert that session 0's late finish does not restore or change session 1:

```swift
context.state.togglePlay()       // session 0
context.state.togglePlay()       // explicit stop: one restore
context.state.togglePlay()       // session 1: hidden again
context.playback.finish(session: 0)
await Task.yield()

XCTAssertEqual(context.application.restoreCallCount, 1)
XCTAssertEqual(context.state.phase, .playing(iteration: 1, currentBlockID: nil))
```

- [ ] **Step 3: Run AppState playback tests and capture RED**

Run: `swift test --filter AppStatePlaybackTests`

Expected: FAIL because playback does not hide Clicker, choose fallback targets, or restore in `AppState`.

- [ ] **Step 4: Implement target selection and generation-owned restoration**

Before `playbackEngine.play`, snapshot fallback, hide Clicker, activate targets, then set playing state and start the engine:

```swift
let fallback = externalApplicationTracker.mostRecentExternalBundleIdentifier
application.hideClicker()
activatePlaybackTarget(saved: script.targetBundleIdentifier, fallback: fallback)
playbackGeneration += 1
let generation = playbackGeneration
phase = .playing(iteration: 1, currentBlockID: nil)
playbackEngine.play(...)
```

Use a helper that filters `nil`, empty strings, and `local.rayscripts.clicker`, preserves saved-first ordering, and de-duplicates equal identifiers. Add a session ownership flag or generation token so the first terminal path clears ownership and calls `application.restoreClicker()`; subsequent stop/finish callbacks do nothing. Explicit stop must invalidate callbacks before calling `playbackEngine.stop()`.

- [ ] **Step 5: Add the failing engine-boundary test**

Update `PlaybackEngineTests` to construct the engine only with timing, poster, and stop monitor. Remove application-controller spies and add a source-level/API assertion through compilation that no application controller initializer is required. Retain all input release, replacement, stop-monitor, duration, and callback tests.

Run: `swift test --filter PlaybackEngineTests`

Expected: the existing engine tests identify the obsolete application-controller initializer/session behavior that must be removed; if the compile-only boundary assertion already passes, add a focused spy assertion that fails because `captureAndActivate(target:)` is still called.

- [ ] **Step 6: Remove playback application sessions from PlaybackEngine**

Delete `applicationSession`, `applicationController`, the four-argument initializer, `captureAndActivate(target:)`, and `session?.restore()`. Then delete `Sources/Clicker/Playback/PlaybackApplicationController.swift` and `Tests/ClickerTests/PlaybackApplicationControllerTests.swift`. Keep task cancellation, generation invalidation, stop-monitor cleanup, and compensating key/mouse releases unchanged.

- [ ] **Step 7: Run playback tests, full suite, and Debug build**

Run: `swift test --filter AppStatePlaybackTests && swift test --filter PlaybackEngineTests && swift test && swift build`

Expected: focused and full tests PASS; Debug build succeeds without application capture/restore in `PlaybackEngine`.

- [ ] **Step 8: Verify sizes, diff, and Git state**

Run: `test ! -e Sources/Clicker/Playback/PlaybackApplicationController.swift && test ! -e Tests/ClickerTests/PlaybackApplicationControllerTests.swift && wc -l Sources/Clicker/App/AppState.swift Sources/Clicker/Playback/PlaybackEngine.swift Tests/ClickerTests/AppStatePlaybackTests.swift Tests/ClickerTests/PlaybackEngineTests.swift && git diff --check && git status --short --branch`

Expected: every Swift file remains below 800 lines and only task files plus required untracked paths are changed.

- [ ] **Step 9: Commit playback focus behavior**

```bash
git add Sources/Clicker/App/AppState.swift Sources/Clicker/Playback/PlaybackEngine.swift Sources/Clicker/Playback/PlaybackApplicationController.swift Tests/ClickerTests/AppStatePlaybackTests.swift Tests/ClickerTests/PlaybackEngineTests.swift Tests/ClickerTests/PlaybackApplicationControllerTests.swift
git commit -m "feat: manage playback application focus"
```

### Task 6: Final Verification and Local App Bundle

**Files:**
- Modify only if verification exposes a defect: the exact production/test files responsible for that defect, using a new RED test before the fix.
- Build artifact: `dist/Clicker.app`

**Interfaces:**
- Verifies all requirements from `docs/superpowers/specs/2026-08-01-external-app-focus-design.md`.
- Produces a locally runnable Debug and Release build plus a rebuilt signed application bundle; performs no remote Git operation.

- [ ] **Step 1: Run the complete automated test suite**

Run: `swift test`

Expected: every test PASS. Record the exact executed/passed test count. The existing SwiftPM `.netrc` warning may remain and must not be “fixed.”

- [ ] **Step 2: Build Debug and Release configurations**

Run: `swift build && swift build -c release`

Expected: both builds complete successfully.

- [ ] **Step 3: Verify Swift file size and clean diffs**

Run: `find Sources Tests -name '*.swift' -print0 | xargs -0 wc -l | awk '$1 >= 800 { print; failed=1 } END { exit failed }' && git diff --check`

Expected: no Swift file is 800 lines or longer and no whitespace errors are reported.

- [ ] **Step 4: Rebuild the local application bundle using the repository procedure**

First read the exact current bundle command from `docs/superpowers/clicker-handoff.md` or the repository build script; run that existing local procedure without modifying signing identity, TCC, `.netrc`, or Git configuration. Do not invent a replacement bundling command.

Expected: `dist/Clicker.app` is recreated from the current Release executable.

- [ ] **Step 5: Verify bundle metadata, signature, and checksum**

Run the repository's documented plist verification, then:

```bash
codesign --verify --deep --strict --verbose=2 dist/Clicker.app
shasum -a 256 dist/Clicker.app/Contents/MacOS/Clicker
```

Expected: plist assertions pass, `codesign` reports validity, and a SHA-256 is printed for the bundled executable.

- [ ] **Step 6: Perform local manual acceptance without changing system permissions**

Using permissions the user has already granted, verify:

1. From an external app, open Clicker, start recording, and confirm Clicker hides while the original external app becomes active.
2. Stop/cancel recording and confirm Clicker returns focused once.
3. Play a script while its saved target is running and confirm that target is activated before input delivery.
4. Quit the saved target, play again, and confirm the recent external fallback is used without launching the missing app.
5. Stop playback and allow another playback to finish naturally; confirm Clicker returns focused once in both cases.

If automation cannot safely prove visual focus behavior, present these exact steps to the user as the remaining manual acceptance instead of claiming they passed.

- [ ] **Step 7: Review final repository evidence**

Run: `git log --oneline -8 && git status --short --branch && git diff HEAD~5..HEAD --stat`

Expected: local feature commits are visible; `.omc/` and `docs/superpowers/clicker-handoff.md` remain untracked; no unrelated or staged changes exist.

- [ ] **Step 8: Request code review and address findings with TDD**

Use `superpowers:requesting-code-review`. For each valid behavioral defect, add and run a failing focused test before changing production code, rerun focused/full verification, and commit exact files with a Conventional Commit. Stop reviewers immediately after they finish, fail, or become unresponsive.
