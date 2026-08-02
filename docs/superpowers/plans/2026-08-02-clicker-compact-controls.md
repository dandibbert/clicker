# Clicker Compact Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the oversized script header and dated shortcut form with compact controls, and add a persistent system/light/dark appearance preference.

**Architecture:** Add an injected appearance-preference store beside the existing shortcut store, expose the preference through `AppState`, and map it to SwiftUI's root `preferredColorScheme`. Keep layout decisions in pure presentation models so the compact header and keycap capture states can be tested before rendering; existing recording, playback, shortcut validation, and script persistence paths remain unchanged.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, XCTest, macOS 14+, Swift Package Manager.

## Global Constraints

- Use only the approved six-color adaptive palette; add no color literals.
- Red is reserved for recording, dangerous actions, and active trails.
- Record and playback remain equal-width, equal-level primary actions.
- The compact script header must fit the 760pt minimum window without clipping and target 88–104pt height.
- The appearance choices are exactly `跟随系统`, `浅色`, and `深色`; the default is `跟随系统`.
- Appearance selection changes Clicker only; never modify macOS system appearance or preferences.
- Preserve shortcut conflict, modifier-only, risky-text-key, persistence, dismissal, and idle-only behavior.
- Preserve repeat-count clamping, repeat-forever, interval clamping, playback progress, editing, and action-list behavior.
- Strict TDD: every production behavior starts with a focused failing test.
- Tests must not post global input, switch real applications, or modify TCC.
- Do not modify `.netrc`, Git identity, `.omc/`, or `docs/superpowers/clicker-handoff.md`; perform no remote Git operations.
- Keep every Swift file below 800 lines and add no third-party dependency or font.

---

### Task 1: Persistent Appearance Preference

**Files:**
- Create: `Sources/Clicker/App/AppAppearancePreference.swift`
- Modify: `Sources/Clicker/App/AppState.swift`
- Modify: `Sources/Clicker/App/ClickerApp.swift`
- Create: `Tests/ClickerTests/AppAppearancePreferenceTests.swift`

**Interfaces:**
- Produces: `enum AppAppearancePreference: String, CaseIterable, Equatable { case system, light, dark }`.
- Produces: `var colorScheme: ColorScheme?` and `var title: String` on `AppAppearancePreference`.
- Produces: `protocol AppAppearancePreferenceProviding: AnyObject { var preference: AppAppearancePreference { get set } }`.
- Produces: `final class AppAppearancePreferenceStore`, backed by injected `UserDefaults` and key `clicker.appearancePreference`.
- Extends: `AppState.init(... appearancePreferenceStore:)` and `@Published var appearancePreference` with immediate persistence.

- [ ] **Step 1: Add failing model and store tests**

Create literal tests:

```swift
import SwiftUI
import XCTest
@testable import Clicker

final class AppAppearancePreferenceTests: XCTestCase {
    func testAppearanceChoicesHaveStableTitlesAndColorSchemes() {
        XCTAssertEqual(AppAppearancePreference.allCases, [.system, .light, .dark])
        XCTAssertEqual(AppAppearancePreference.system.title, "跟随系统")
        XCTAssertEqual(AppAppearancePreference.light.title, "浅色")
        XCTAssertEqual(AppAppearancePreference.dark.title, "深色")
        XCTAssertNil(AppAppearancePreference.system.colorScheme)
        XCTAssertEqual(AppAppearancePreference.light.colorScheme, .light)
        XCTAssertEqual(AppAppearancePreference.dark.colorScheme, .dark)
    }

    func testStoreDefaultsToSystemAndPersistsASelection() {
        let suite = "Clicker-Appearance-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppAppearancePreferenceStore(defaults: defaults)
        XCTAssertEqual(store.preference, .system)
        store.preference = .dark
        XCTAssertEqual(AppAppearancePreferenceStore(defaults: defaults).preference, .dark)
    }

    func testStoreFallsBackToSystemForUnknownPersistedValue() {
        let suite = "Clicker-Appearance-Invalid-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("sepia", forKey: "clicker.appearancePreference")
        XCTAssertEqual(AppAppearancePreferenceStore(defaults: defaults).preference, .system)
    }
}
```

- [ ] **Step 2: Run RED**

Run: `swift test --filter AppAppearancePreferenceTests`

Expected: compilation fails because `AppAppearancePreference` and `AppAppearancePreferenceStore` do not exist.

- [ ] **Step 3: Implement the preference boundary**

Implement stable raw values, titles, `ColorScheme?`, injected defaults, and fallback:

```swift
enum AppAppearancePreference: String, CaseIterable, Equatable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
```

The store getter decodes the raw string or returns `.system`; the setter writes the raw string.

- [ ] **Step 4: Add failing AppState persistence test**

Add an injected stub test proving initial load and immediate save:

```swift
@MainActor
func testAppStateLoadsAndPersistsAppearancePreference() {
    let appearanceStore = AppearanceStoreStub(preference: .dark)
    let state = makeState(appearancePreferenceStore: appearanceStore)
    XCTAssertEqual(state.appearancePreference, .dark)
    state.appearancePreference = .light
    XCTAssertEqual(appearanceStore.preference, .light)
}
```

- [ ] **Step 5: Run RED, then wire AppState and root color scheme**

Run: `swift test --filter AppAppearancePreferenceTests`

Expected RED: `AppState` has no `appearancePreferenceStore` parameter or published preference.

Add the injected store, initialize `@Published` from it, persist in `didSet`, and apply:

```swift
MainView()
    .environmentObject(state)
    .preferredColorScheme(state.appearancePreference.colorScheme)
```

- [ ] **Step 6: Run GREEN and commit**

Run: `swift test --filter AppAppearancePreferenceTests && swift test --filter AppState && swift build`

Expected: all selected tests pass and Debug build succeeds.

```bash
git add Sources/Clicker/App/AppAppearancePreference.swift Sources/Clicker/App/AppState.swift Sources/Clicker/App/ClickerApp.swift Tests/ClickerTests/AppAppearancePreferenceTests.swift
git commit -m "feat: add persistent appearance preference"
```

---

### Task 2: Compact Single-Row Script Header

**Files:**
- Modify: `Sources/Clicker/UI/ScriptHeaderView.swift`
- Modify: `Sources/Clicker/UI/PrimaryActionBar.swift`
- Modify: `Sources/Clicker/UI/ClickerVisualTheme.swift`
- Modify: `Tests/ClickerTests/VisualPresentationTests.swift`
- Modify: `Tests/ClickerTests/FinalVisualConsumerTests.swift`

**Interfaces:**
- Produces: `CompactScriptHeaderPresentation` with `title`, `metadata`, and `showsPlaybackProgress`.
- Produces: `ClickerVisualTheme.compactHeaderHeight` in the inclusive 88–104pt range.
- Preserves: `PrimaryActionPresentation.pair`, `.toggleRecord`, `.togglePlay`, `ScriptPlaybackEligibility`, and all repeat bindings.

- [ ] **Step 1: Add failing compact-header presentation tests**

Add tests asserting the exact compact contract:

```swift
func testCompactHeaderCombinesActionCountAndDurationMetadata() {
    let script = Script(
        name: "录制 1",
        blocks: [.wait(WaitBlock(duration: 1.5))],
        trailingDelay: 0.5
    )
    let model = CompactScriptHeaderPresentation(script: script, phase: .idle)
    XCTAssertEqual(model.title, "录制 1")
    XCTAssertEqual(model.metadata, "1 个动作 · 约 2.0 秒")
    XCTAssertFalse(model.showsPlaybackProgress)
}

func testCompactHeaderHeightStaysInsideApprovedRange() {
    XCTAssertGreaterThanOrEqual(ClickerVisualTheme.compactHeaderHeight, 88)
    XCTAssertLessThanOrEqual(ClickerVisualTheme.compactHeaderHeight, 104)
}
```

Also cover playing finite and infinite repeat progress without changing existing copy.

- [ ] **Step 2: Run RED**

Run: `swift test --filter VisualPresentationTests`

Expected: compilation fails because `CompactScriptHeaderPresentation` and `compactHeaderHeight` do not exist.

- [ ] **Step 3: Implement the pure presentation and compact layout**

Replace the vertical three-section header with one `HStack`:

```text
[title + metadata]  [record][play]  [repeat][∞][interval][progress]
```

Use a fixed header height token, 8–12pt internal spacing, the existing equal action bar, 44pt minimum interactive height, 44–50pt numeric fields, and layout priorities that shrink metadata before actions or settings. Keep the existing header background and a bottom separator; remove vertical empty space.

- [ ] **Step 4: Add a failing 760×480 consumer render test**

Render a selected multi-action script at logical 760×480 in Aqua and Dark Aqua. Assert:

- the header pixel height is at most 104pt;
- both primary action labels are present inside the header bounds;
- repeat and interval controls remain inside the viewport;
- the action-list content begins below the header and has more vertical pixels than the previous 316pt header baseline.

Run: `swift test --filter FinalVisualConsumerTests`

Expected RED: existing header exceeds the compact height assertion.

- [ ] **Step 5: Preserve behavior and verify GREEN**

Run: `swift test --filter VisualPresentationTests && swift test --filter FinalVisualConsumerTests && swift test --filter AppStatePlaybackTests && swift test --filter AppStateRecordingTests && swift build`

Expected: all selected tests pass; notification wiring, eligibility, clamping, and build remain green.

- [ ] **Step 6: Commit**

```bash
git add Sources/Clicker/UI/ScriptHeaderView.swift Sources/Clicker/UI/PrimaryActionBar.swift Sources/Clicker/UI/ClickerVisualTheme.swift Tests/ClickerTests/VisualPresentationTests.swift Tests/ClickerTests/FinalVisualConsumerTests.swift
git commit -m "feat: compact the script control header"
```

---

### Task 3: Keycap Shortcut Capture and Appearance Settings

**Files:**
- Modify: `Sources/Clicker/UI/RecordingSettingsView.swift`
- Create: `Sources/Clicker/UI/ShortcutKeycapView.swift`
- Modify: `Tests/ClickerTests/ShortcutCaptureTests.swift`
- Modify: `Tests/ClickerTests/VisualPresentationTests.swift`
- Modify: `Tests/ClickerTests/FinalVisualConsumerTests.swift`

**Interfaces:**
- Produces: `ShortcutKeycapPresentation` with `keys: [String]`, `title`, `instruction`, and `accessibilityLabel`.
- Produces: `ShortcutCaptureCard` driven by `isCapturing`, the current shortcut, and one tap action.
- Consumes: `AppAppearancePreference.allCases`, `title`, and `AppState.appearancePreference` from Task 1.
- Preserves: `RecordingShortcutEditor.accept`, `restoreDefault`, and hidden `ShortcutCaptureView` event capture.

- [ ] **Step 1: Add failing keycap presentation tests**

Cover stable modifier order and capture copy:

```swift
func testShortcutPresentationUsesSeparateOrderedKeycaps() {
    let shortcut = RecordingStopShortcut(
        keyCode: 14,
        modifierFlags: KeyCodeMap.maskControl
            | KeyCodeMap.maskOption
            | KeyCodeMap.maskShift
            | KeyCodeMap.maskCommand
    )
    let model = ShortcutKeycapPresentation(shortcut: shortcut, isCapturing: false)
    XCTAssertEqual(model.keys, ["⌃", "⌥", "⇧", "⌘", "E"])
    XCTAssertEqual(model.title, "停止录制快捷键")
    XCTAssertEqual(model.instruction, "点击重新录入")
    XCTAssertTrue(model.accessibilityLabel.contains(shortcut.displayName))
}

func testCapturingPresentationPromptsForACombination() {
    let model = ShortcutKeycapPresentation(shortcut: .defaultValue, isCapturing: true)
    XCTAssertEqual(model.instruction, "请按下新的组合键…")
}
```

- [ ] **Step 2: Run RED**

Run: `swift test --filter ShortcutCaptureTests`

Expected: compilation fails because `ShortcutKeycapPresentation` does not exist.

- [ ] **Step 3: Implement key decomposition and capture card**

Map modifiers in the fixed order control, option, shift, command, followed by `KeyCodeMap.displayName(for:)`. Build each token with approved card surface, separator, monospaced semibold text, 6–8pt corner radius, and at least 30pt height. The entire card is one button; when capturing, retain its dimensions and show a clear listening state without animation that changes layout.

- [ ] **Step 4: Add failing appearance-picker consumer tests**

Add tests that inspect the real settings consumer and render it in both color schemes:

```swift
func testRecordingSettingsOffersAllThreeAppearanceChoices() {
    XCTAssertEqual(AppAppearancePreference.allCases.map(\.title), [
        "跟随系统", "浅色", "深色"
    ])
}
```

The consumer structure/raster must find the “外观” label and all three segment titles, and must no longer find a separate “当前快捷键” row plus “更改快捷键” button.

Run: `swift test --filter VisualPresentationTests && swift test --filter FinalVisualConsumerTests`

Expected RED: the settings view has no appearance picker and still renders the legacy shortcut form.

- [ ] **Step 5: Recompose the settings page**

Place an appearance panel first with:

```swift
Picker("外观", selection: $state.appearancePreference) {
    ForEach(AppAppearancePreference.allCases, id: \.self) { preference in
        Text(preference.title).tag(preference)
    }
}
.pickerStyle(.segmented)
```

Place the single shortcut capture card below it, followed by the existing warning/help message. Keep scrollable content and the fixed safe-area footer. Remove the old current-shortcut row and separate change button.

- [ ] **Step 6: Run behavior, accessibility, and layout verification**

Run:

```bash
swift test --filter ShortcutCaptureTests && \
swift test --filter AppAppearancePreferenceTests && \
swift test --filter VisualPresentationTests && \
swift test --filter FinalVisualConsumerTests && \
swift test --filter AppState && \
swift build
```

Expected: all selected tests and Debug build pass. The maximum accessibility-size 440×360 settings render keeps the appearance picker, capture card, Restore Defaults, and Done reachable.

- [ ] **Step 7: Commit**

```bash
git add Sources/Clicker/UI/RecordingSettingsView.swift Sources/Clicker/UI/ShortcutKeycapView.swift Tests/ClickerTests/ShortcutCaptureTests.swift Tests/ClickerTests/VisualPresentationTests.swift Tests/ClickerTests/FinalVisualConsumerTests.swift
git commit -m "feat: modernize clicker settings controls"
```

---

### Task 4: Final Verification, Bundle, and Visual QA

**Files:**
- Modify only after a verified RED: exact responsible source and test files.
- Build artifact: `dist/Clicker.app`.

**Interfaces:**
- Verifies the approved compact-controls design in light, dark, and system modes.
- Produces a locally runnable, ad-hoc-signed Clicker bundle.

- [ ] **Step 1: Run the complete suite and both builds**

Run: `swift test && swift build && swift build -c release`

Expected: all XCTest cases pass and both builds exit 0. Leave the existing `.netrc` warning unchanged.

- [ ] **Step 2: Run structural gates**

```bash
find Sources Tests -name '*.swift' -print0 | xargs -0 wc -l | awk '$2 != "total" && $1 >= 800 { print; failed=1 } END { exit failed }'
git diff --check
git status --short --branch
```

Expected: no Swift file reaches 800 lines, no whitespace error exists, and only the two pre-existing untracked paths remain.

- [ ] **Step 3: Rebuild and verify the app bundle**

```bash
./scripts/build-app.sh
plutil -lint dist/Clicker.app/Contents/Info.plist
test "$(plutil -extract CFBundleIconFile raw -o - dist/Clicker.app/Contents/Info.plist)" = "Clicker"
test -s dist/Clicker.app/Contents/Resources/Clicker.icns
codesign --verify --deep --strict --verbose=2 dist/Clicker.app
shasum -a 256 dist/Clicker.app/Contents/MacOS/Clicker
```

Expected: bundle, icon, plist, and strict signature pass; record the executable SHA-256.

- [ ] **Step 4: Render and inspect final states**

Using the existing safe local `NSHostingView` renderer, without calling recording or playback APIs, capture:

- selected script at 760×480 in light and dark appearances;
- selected script at 1120×720;
- settings at 440×360 in system/light/dark choices;
- settings at maximum accessibility size;
- shortcut capture idle and listening states.

Verify header height, reclaimed action-list space, equal actions, no clipping, stable keycaps, readable warnings, fixed footer, and immediate root color-scheme mapping. Store screenshots under the ignored plan workspace and do not commit them.

- [ ] **Step 5: Run final review and close verified defects with TDD**

Request a whole-branch architecture, accessibility, behavior, and visual-consistency review. Any Critical or Important defect must receive a focused failing regression test before production changes, then focused/full verification and an exact-file commit.

- [ ] **Step 6: Manual acceptance boundary**

Report these as manual, not automated: live system appearance changes, actual global shortcut capture, real recording/countdown/playback/stop, Finder/Dock icon, VoiceOver, keyboard focus, and interactive resizing/long-list scrolling.
