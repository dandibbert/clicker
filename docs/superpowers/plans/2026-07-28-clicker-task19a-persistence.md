# Clicker Task 19A Persistence Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make script loading, saving, and deletion transactional, observable, and resistant to corrupt files and stale updates.

**Architecture:** `ScriptStore` returns structured load results and performs explicit same-directory temporary writes followed by atomic replacement through an injectable filesystem boundary. `AppState` treats disk success as the commit point, separates creation from ID-based updates, and publishes one structured persistence issue for SwiftUI to present.

**Tech Stack:** Swift 5.9, Foundation FileManager/JSONEncoder/JSONDecoder, SwiftUI, XCTest, macOS 14+.

## Global Constraints

- Strict TDD: each behavior change begins with a focused failing test.
- Never update the in-memory script library before the corresponding disk operation succeeds.
- Never silently discard directory, read, decode, encode, temporary-write, replace, or delete failures.
- Keep `.omc/` and `docs/superpowers/clicker-handoff.md` untracked.
- Do not modify TCC, `.netrc`, Git identity, or perform remote Git operations.
- Keep every Swift file below 800 lines and use exact-path staging only.

---

### Task 1: Structured Load Results

**Files:**
- Modify: `Sources/ClickerCore/Storage/ScriptStore.swift`
- Modify: `Tests/ClickerCoreTests/ScriptStoreTests.swift`

**Interfaces:**
- Produces `ScriptStoreIssue` with `operation`, optional `fileName`, and `message`.
- Produces `ScriptStoreLoadResult { scripts: [Script], issues: [ScriptStoreIssue] }`.
- Changes `ScriptStore.loadAll()` to return `ScriptStoreLoadResult`.

- [ ] Add failing tests asserting corrupt JSON returns the good script plus a `.decode` issue naming `bad.json`, and an unreadable/missing directory operation returns a `.list` issue rather than an empty-success result.
- [ ] Run `swift test --filter ScriptStoreTests` and confirm type/behavior failures.
- [ ] Implement the result/issue value types and make every load failure explicit while retaining successfully decoded scripts sorted by creation time.
- [ ] Update existing ScriptStore callers/tests to consume `.scripts` and `.issues` without adding UI behavior yet.
- [ ] Run `swift test --filter ScriptStoreTests` and commit `feat: return structured script load issues`.

### Task 2: Explicit Atomic Save Pipeline

**Files:**
- Create: `Sources/ClickerCore/Storage/ScriptStoreFileSystem.swift`
- Modify: `Sources/ClickerCore/Storage/ScriptStore.swift`
- Modify: `Tests/ClickerCoreTests/ScriptStoreTests.swift`

**Interfaces:**
- Produces internal `ScriptStoreFileSystem` methods for directory creation, listing, reading, temporary writing, atomic replacement/move, existence, and removal.
- `ScriptStore.save(_:)` continues to throw, but throws `ScriptStoreIssue` with `.encode`, `.temporaryWrite`, or `.replace`.

- [ ] Add a failing fake-filesystem test where temporary writing records only a prefix then throws; assert the original destination remains unchanged and the thrown operation is `.temporaryWrite`.
- [ ] Add a failing replacement-error test; assert the old destination remains and the error operation is `.replace`.
- [ ] Run the two focused tests and confirm failures before production changes.
- [ ] Implement encode-first, unique same-directory temp write, atomic replace/move, and best-effort temp cleanup. Never write the destination directly.
- [ ] Run all `ScriptStoreTests`, then commit `feat: save scripts through atomic replacement`.

### Task 3: Transactional AppState Mutations

**Files:**
- Modify: `Sources/Clicker/App/AppState.swift`
- Create: `Tests/ClickerTests/AppStatePersistenceTests.swift`
- Modify: recording/duplication callers in `Sources/Clicker/App/AppState.swift`

**Interfaces:**
- Produces `ScriptPersisting` for AppState injection.
- Produces `AppState.create(_:)`, retains `AppState.update(_:)` for existing IDs only, and publishes `persistenceIssue: ScriptStoreIssue?`.

- [ ] Add failing tests proving failed create/save leaves `scripts` and selection unchanged; failed update preserves the prior in-memory script; successful update resolves the current index by script ID after saving.
- [ ] Add a failing stale-update test: delete a script successfully, then submit an old copy to `update`; assert it is not saved or reinserted.
- [ ] Run `swift test --filter AppStatePersistenceTests` and confirm current optimistic mutations fail.
- [ ] Implement save-first create/update paths, split recording/duplication to call create, and reject updates for missing IDs.
- [ ] Run AppState persistence/recording/playback tests and commit `feat: commit script updates after persistence`.

### Task 4: Transactional Delete and Error Presentation

**Files:**
- Modify: `Sources/Clicker/App/AppState.swift`
- Modify: `Sources/Clicker/UI/MainView.swift`
- Modify: `Tests/ClickerTests/AppStatePersistenceTests.swift`

**Interfaces:**
- `deleteScript(id:)` removes memory only after store deletion succeeds.
- `persistenceIssue` is rendered as a dismissible SwiftUI alert with operation-specific text.

- [ ] Add a failing delete-error test asserting script and selection remain unchanged and `.delete` is published.
- [ ] Add a failing reload test asserting good scripts remain visible while corrupt/load issues are published rather than silently ignored.
- [ ] Run focused tests and confirm failures.
- [ ] Implement disk-first deletion, structured issue publication, and one alert binding in `MainView`.
- [ ] Run AppState tests, `swift test`, `swift build`, `git diff --check`, Swift line-count check, and git status.
- [ ] Perform sequential spec/code-quality review; every Critical/Important finding gets a failing regression test before a fix.
- [ ] Commit `feat: surface script persistence failures`.

## Self-Review

- Spec coverage: partial writes, replacement errors, corrupt JSON, directory/read failures, save/delete UI consistency, ID-based updates, and stale post-delete updates each have an explicit red-green task.
- Placeholder scan: no deferred implementation placeholders.
- Type consistency: store issues/results feed the AppState protocol and the single SwiftUI error presentation path.
