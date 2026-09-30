# Recording and playback reliability fixes (2026-09-30)

The changes address the audit of commit `a0520d15d923bb00a448b974a4f44cf487f3442e`.

## Behavior changes

- Editing a wait or timed action keeps its start and its original overlapping group. Later, non-overlapping actions move by the change in that group's end. Existing gaps, suffix overlaps, and the script's trailing delay remain intact.
- Generated text has canonical keystroke timing and ordinals before timeline insertion. Replacing text replaces the old captured characters, including in the saved JSON; unchanged text retains captured timing.
- Saving a closed-loop or zero-span drag without changes preserves its path. Duration-only edits do not change coordinates.
- Unicode capture queries the full UTF-16 length before allocating a buffer and bounds decoding to that buffer. Playback preserves the recorded autorepeat flag, including recordings that start with a repeated key-down.
- A failed recording save retains a clearly marked in-memory draft. The recovery banner offers retry, save elsewhere, and confirmed discard. A new recording cannot replace it. This is not crash recovery: forced termination or a system crash can still lose an unsaved in-memory draft.
- Normal quit stops recording before opening a save/cancel/discard dialog, so dialog interactions are not recorded. Cancel leaves the stopped draft available; save failure cancels exit. Playback releases held inputs synchronously before termination.
- A failed recorder start reports an error. An interrupted event tap saves only the captured portion, with a persistent partial-recording reason and a visible warning.
- Shortcut playback retains the sidebar selection. A separate session snapshot identifies the script actually running; unrelated selected scripts no longer show its progress or highlight. A banner can reveal or stop the running script.
- A queued stop-monitor callback from a previous session cannot stop a newer session.

## Existing focus policy

Target-application activation keeps the existing documented policy: try the saved target and the available fallback, then continue if neither activates. No focus-confirmation guarantee has been added. Check the frontmost application before playback, especially when the saved target has quit. Changing this policy to fail closed or adding an explicit current-application fallback remains a separate product decision.

## Regression coverage and manual acceptance

The regression tests use fake storage, clocks, application controllers and event-tap sessions. Constructed CGEvents are inspected without posting input. They cover duration edits and overlaps, generated-text insertion/copy/move/order and serialization, drag geometry, Unicode capture, autorepeat and release deduplication, stale stop callbacks, draft retry/export/discard, cancellable termination, partial metadata, and cross-script playback progress.

Run the normal checks on macOS:

```sh
swift test
python3 -B -m unittest discover -s Tests/Packaging -v
bash -n scripts/build-app.sh scripts/build-icon.sh scripts/package-release.sh
```

For the Unicode memory-safety regression, also run:

```sh
swift test --sanitize=address --filter EventRecorderTests
```

Native validation still needs a real macOS desktop: permissions grant/revocation, actual input capture/posting, quit and recovery dialogs, long recordings, target focus/Spaces, multiple displays, non-US layouts and input methods. CI unit tests and ad-hoc-signed packages do not establish these device-level results or Apple notarization.
