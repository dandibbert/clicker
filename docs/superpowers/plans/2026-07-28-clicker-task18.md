# Clicker Task 18 Safe Playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make playback preserve the full plan duration, remain promptly cancellable, release all held input safely, ignore synthetic Escape, and restore foreground applications deterministically.

**Architecture:** Keep `BlockExpander` as the pure plan builder. Refactor `PlaybackEngine` around injected timing, event posting, stop monitoring, and application-control protocols; keep held-input accounting in a separate pure tracker so cancellation and replacement cleanup are deterministic and testable without global input. AppKit/CoreGraphics adapters remain thin production-only boundaries.

**Tech Stack:** Swift 5.9, Swift concurrency, AppKit, CoreGraphics, XCTest, macOS 14+.

## Global Constraints

- Strict TDD: every behavior change starts with a focused failing test.
- Tests must never post real keyboard or mouse events.
- Preserve schema-v4 absolute timing and ordinal ordering.
- Cancellation, replacement, Escape, and termination release each held input exactly once.
- Wait-only and trailing-only plans must wait for `PlaybackPlan.duration`.
- Repeat interval begins only after the full plan duration has elapsed.
- Do not modify TCC, `.netrc`, Git identity, or perform remote Git operations.
- Keep every Swift file below 800 lines and `.omc/` untracked.

---

### Task 1: Injectable Playback Boundaries and Full Plan Duration

**Files:**
- Create: `Sources/Clicker/Playback/PlaybackDependencies.swift`
- Modify: `Sources/Clicker/Playback/PlaybackEngine.swift`
- Create: `Tests/ClickerTests/PlaybackEngineTests.swift`

**Interfaces:**
- Consumes: `PlaybackPlan`, `PlaybackStep`, `StepAction` from `ClickerCore`.
- Produces: `PlaybackTiming`, `PlaybackEventPosting`, `PlaybackStopMonitoring`, and injectable `PlaybackEngine.init(...)`.

- [ ] **Step 1: Write failing tests for wait-only and trailing-only plans**

Use a fake timing dependency whose `sleep(until:)` advances an in-memory monotonic clock, and a fake poster that only records `StepAction` values. Assert that a wait-only script posts nothing but sleeps to its duration, and a trailing-only script also waits to its duration before `onFinish`.

```swift
func testWaitOnlyPlanCompletesOnlyAfterPlanDuration() async {
    let timing = TestPlaybackTiming()
    let poster = RecordingPlaybackPoster()
    let engine = PlaybackEngine(timing: timing, poster: poster, stopMonitor: NoopStopMonitor())
    let script = Script(name: "wait", blocks: [.wait(WaitBlock(duration: 2))])

    await playToCompletion(engine, script: script)

    XCTAssertEqual(timing.deadlines, [2])
    XCTAssertTrue(poster.actions.isEmpty)
}
```

- [ ] **Step 2: Run the focused tests and verify the current empty-step guard fails**

Run: `swift test --filter PlaybackEngineTests.testWaitOnlyPlanCompletesOnlyAfterPlanDuration`

Expected: FAIL because `PlaybackEngine` has no injectable initializer and currently finishes immediately when `steps` is empty.

- [ ] **Step 3: Add minimal protocols and make PlaybackEngine consume `BlockExpander.plan(...)`**

```swift
@MainActor protocol PlaybackTiming: AnyObject {
    var now: TimeInterval { get }
    func sleep(until deadline: TimeInterval) async throws
    func cooperativeYield() async
}

@MainActor protocol PlaybackEventPosting: AnyObject {
    func post(_ action: StepAction)
}
```

The system timing adapter uses a monotonic uptime clock and cancellation-aware `Task.sleep`. The engine waits to `iterationStart + plan.duration` after all steps, even when there are no steps.

- [ ] **Step 4: Verify focused tests pass**

Run: `swift test --filter PlaybackEngineTests`

- [ ] **Step 5: Add a failing repeat-interval test, then implement it**

Assert deadlines for a two-iteration, 1-second plan with a 0.5-second repeat interval are `[1.0, 1.5, 2.5]`; the interval begins after the first plan completes.

- [ ] **Step 6: Add a failing dense-equal-time test, then yield after every posted step**

Record yield count independently of post count. Three equal-time steps must post in stable plan order and perform at least three cooperative yields so cancellation can run.

- [ ] **Step 7: Commit**

```bash
git add Sources/Clicker/Playback/PlaybackDependencies.swift Sources/Clicker/Playback/PlaybackEngine.swift Tests/ClickerTests/PlaybackEngineTests.swift
git commit -m "feat: run complete playback plans with injected timing"
```

---

### Task 2: Held-Input Tracking and Compensation

**Files:**
- Create: `Sources/Clicker/Playback/PressedInputTracker.swift`
- Create: `Tests/ClickerTests/PressedInputTrackerTests.swift`
- Modify: `Sources/Clicker/Playback/PlaybackEngine.swift`
- Modify: `Tests/ClickerTests/PlaybackEngineTests.swift`

**Interfaces:**
- Consumes: posted `StepAction` values in exact playback order.
- Produces: `PressedInputTracker.observe(_:)` and `releaseActions() -> [StepAction]`, where reading release actions drains state.

- [ ] **Step 1: Write failing tracker tests**

Cover key down/up, repeated down deduplication, left/right mouse down, latest drag location, and deterministic release actions.

```swift
func testReleaseActionsDrainHeldKeysAndMouseButtonsExactlyOnce() {
    var tracker = PressedInputTracker()
    tracker.observe(.keyDown(keyCode: 4, flags: 0, chars: "h"))
    tracker.observe(.mouseDown(x: 10, y: 20, button: .left, clickCount: 1, flags: 0))

    XCTAssertEqual(tracker.releaseActions().count, 2)
    XCTAssertTrue(tracker.releaseActions().isEmpty)
}
```

- [ ] **Step 2: Run tracker tests and verify missing type failure**

Run: `swift test --filter PressedInputTrackerTests`

- [ ] **Step 3: Implement the pure tracker and verify green**

Track keys by key code and mouse buttons by button. A normal up removes state; drag updates the matching button’s release coordinates. `releaseActions()` clears before returning.

- [ ] **Step 4: Write failing engine cancellation and replacement tests**

Cancel after a key-down or mouse-down but before the captured up. Assert one compensating up is posted. Start a replacement session and assert the old session releases before new session input, with no duplicate release from the old task’s deferred cleanup.

- [ ] **Step 5: Integrate tracker cleanup through one generation-gated path**

`stop()`, replacement, Escape, natural completion, and termination all call one idempotent session cleanup. Natural completion drains no already-released inputs; cancellation drains held inputs once.

- [ ] **Step 6: Verify tests and commit**

```bash
swift test --filter 'PressedInputTrackerTests|PlaybackEngineTests'
git add Sources/Clicker/Playback/PressedInputTracker.swift Sources/Clicker/Playback/PlaybackEngine.swift Tests/ClickerTests/PressedInputTrackerTests.swift Tests/ClickerTests/PlaybackEngineTests.swift
git commit -m "feat: release held input when playback stops"
```

---

### Task 3: Escape Monitoring Without Synthetic Self-Cancellation

**Files:**
- Create: `Sources/Clicker/Playback/PlaybackStopMonitor.swift`
- Create: `Tests/ClickerTests/PlaybackStopMonitorTests.swift`
- Modify: `Sources/Clicker/Playback/PlaybackEngine.swift`

**Interfaces:**
- Consumes: AppKit local/global key-down events.
- Produces: `PlaybackStopMonitoring.start(onStop:)` and `stop()`, plus pure Escape classification using key code and `.eventSourceUserData`.

- [ ] **Step 1: Write a failing pure classification test**

Create CGEvents without posting them. A hardware Escape (`keyCode == 53`, no synthetic marker) returns true; an Escape marked with `EventRecorder.syntheticMarker` returns false; other keys return false.

- [ ] **Step 2: Verify red, then implement the AppKit adapter**

The local monitor only swallows a hardware Escape. Synthetic Escape is returned to the app and never invokes playback stop.

- [ ] **Step 3: Inject the monitor into PlaybackEngine and test callback cleanup**

Use a fake monitor to trigger stop deterministically. Assert monitor removal and `onFinish` occur once.

- [ ] **Step 4: Verify and commit**

```bash
swift test --filter 'PlaybackStopMonitorTests|PlaybackEngineTests'
git add Sources/Clicker/Playback/PlaybackStopMonitor.swift Sources/Clicker/Playback/PlaybackEngine.swift Tests/ClickerTests/PlaybackStopMonitorTests.swift Tests/ClickerTests/PlaybackEngineTests.swift
git commit -m "feat: ignore synthetic escape during playback"
```

---

### Task 4: Foreground Application Activation and Restoration

**Files:**
- Create: `Sources/Clicker/Playback/PlaybackApplicationController.swift`
- Create: `Tests/ClickerTests/PlaybackApplicationControllerTests.swift`
- Modify: `Sources/Clicker/Playback/PlaybackEngine.swift`
- Modify: `Tests/ClickerTests/PlaybackEngineTests.swift`

**Interfaces:**
- Consumes: `Script.targetBundleIdentifier` and current frontmost bundle identifier.
- Produces: `PlaybackApplicationControlling.captureAndActivate(target:) -> PlaybackApplicationSession` and idempotent `restore()`.

- [ ] **Step 1: Write failing engine integration tests**

Assert the previous foreground application is captured before target activation. Natural completion, cancellation, and replacement each restore the previous application at most once. A nil or missing target performs no activation but still has deterministic cleanup.

- [ ] **Step 2: Run tests and verify missing dependency behavior**

Run: `swift test --filter PlaybackEngineTests`

- [ ] **Step 3: Implement the AppKit adapter using official NSRunningApplication activation APIs**

Resolve the saved bundle identifier with `NSRunningApplication.runningApplications(withBundleIdentifier:)`. Capture the prior frontmost bundle before activation. The per-playback session guards restoration with a boolean.

- [ ] **Step 4: Verify and commit**

```bash
swift test --filter 'PlaybackApplicationControllerTests|PlaybackEngineTests'
git add Sources/Clicker/Playback/PlaybackApplicationController.swift Sources/Clicker/Playback/PlaybackEngine.swift Tests/ClickerTests/PlaybackApplicationControllerTests.swift Tests/ClickerTests/PlaybackEngineTests.swift
git commit -m "feat: activate and restore playback target applications"
```

---

### Task 5: AppState Termination Integration and Task 18 Verification

**Files:**
- Modify: `Sources/Clicker/App/AppState.swift`
- Modify: `Tests/ClickerTests/AppStateRecordingTests.swift`
- Create: `Tests/ClickerTests/AppStatePlaybackTests.swift`

**Interfaces:**
- Consumes: the refactored injectable `PlaybackEngine` stop contract.
- Produces: app-termination cleanup and correct idle phase transitions.

- [ ] **Step 1: Write failing AppState tests**

Inject a playback engine protocol fake. Verify application termination stops active playback once, UI/hotkey replacement does not double-finish, and trailing-only scripts are accepted for playback even when `blocks` is empty.

- [ ] **Step 2: Verify red and implement the smallest AppState changes**

Observe `NSApplication.willTerminateNotification`, call the engine’s idempotent stop, and change the playback guard from `!blocks.isEmpty` to a positive `PlaybackPlan.duration` or nonempty steps.

- [ ] **Step 3: Run focused and full verification**

```bash
swift test --filter 'PlaybackEngineTests|PressedInputTrackerTests|PlaybackStopMonitorTests|PlaybackApplicationControllerTests|AppStatePlaybackTests'
swift test
swift build
git diff --check
find Sources Tests -name '*.swift' -print0 | xargs -0 wc -l | sort -nr | head
git status --short --branch
```

- [ ] **Step 4: Run sequential spec and code-quality reviews**

Review Task 18 requirements only. Every Critical/Important finding receives a failing regression test before a fix and a fresh verification run.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clicker/App/AppState.swift Tests/ClickerTests/AppStatePlaybackTests.swift
git commit -m "feat: integrate safe playback lifecycle"
```

## Self-Review

- Spec coverage: full plan duration, repeat interval, cooperative yield, injected poster/timing, held-input compensation, replacement/cancel/termination, synthetic Escape, target activation, single restoration, finite/infinite deterministic tests are each assigned above.
- Placeholder scan: no deferred implementation placeholders are present.
- Type consistency: all later tasks consume the dependency protocols introduced in Task 1 and the tracker interface introduced in Task 2.
