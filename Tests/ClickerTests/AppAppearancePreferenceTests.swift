import SwiftUI
import XCTest
@testable import Clicker
import ClickerCore

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

    @MainActor
    func testAppStateLoadsAndPersistsAppearancePreference() {
        let appearanceStore = AppearanceStoreStub(preference: .dark)
        let state = makeState(appearancePreferenceStore: appearanceStore)
        XCTAssertEqual(state.appearancePreference, .dark)
        state.appearancePreference = .light
        XCTAssertEqual(appearanceStore.preference, .light)
    }

    @MainActor
    private func makeState(
        appearancePreferenceStore: AppAppearancePreferenceProviding
    ) -> AppState {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-Appearance-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AppState(
            store: ScriptStore(directory: directory),
            appearancePreferenceStore: appearancePreferenceStore
        )
    }
}

private final class AppearanceStoreStub: AppAppearancePreferenceProviding {
    var preference: AppAppearancePreference

    init(preference: AppAppearancePreference) {
        self.preference = preference
    }
}
