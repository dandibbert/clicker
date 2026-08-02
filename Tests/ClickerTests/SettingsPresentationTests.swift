import XCTest
@testable import Clicker

final class SettingsPresentationTests: XCTestCase {
    func testRecordingSettingsOffersAllThreeAppearanceChoices() {
        XCTAssertEqual(
            AppAppearancePreference.allCases.map(\.title),
            ["跟随系统", "浅色", "深色"]
        )
    }

    @MainActor
    func testRecordingSettingsUsesAppearancePickerAndSingleShortcutCaptureCard() {
        let body = String(reflecting: RecordingSettingsView.Body.self)

        XCTAssertTrue(body.contains("Picker"), body)
        XCTAssertTrue(body.contains("ShortcutCaptureCard"), body)
        XCTAssertTrue(body.contains("ScrollView"), body)
        XCTAssertTrue(body.contains("_InsetViewModifier"), body)
    }
}
