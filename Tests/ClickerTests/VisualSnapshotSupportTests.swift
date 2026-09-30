import AppKit
import SwiftUI
import XCTest
@testable import Clicker

final class VisualSnapshotSupportTests: XCTestCase {
    @MainActor
    func testSnapshotHasStableTwoPixelsPerPointRegardlessOfScreen() throws {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: Color(red: 1, green: 0, blue: 0).frame(width: 80, height: 40))
        hosting.frame = CGRect(x: 0, y: 0, width: 80, height: 40)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try retinaBitmap(for: hosting)
        XCTAssertEqual(bitmap.pixelsWide, 160)
        XCTAssertEqual(bitmap.pixelsHigh, 80)
        XCTAssertEqual(bitmap.size, hosting.bounds.size)
        let center = try XCTUnwrap(bitmap.colorAt(x: 80, y: 40)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(center.redComponent, 0.9)
        XCTAssertLessThan(center.greenComponent, 0.1)
    }

    func testMetadataNormalizationAcceptsVisionTraditionalGlyphButPreservesContent() {
        XCTAssertEqual(normalizedVisualText("1 个动作 • 約 1.0 秒"), "1个动作•约1.0秒")
        XCTAssertEqual(normalizedVisualText("1 个动作 • 约 1.0 秒"), "1个动作•约1.0秒")
        XCTAssertEqual(normalizedVisualText("◎ 录制"), "录制")
        XCTAssertNotEqual(normalizedVisualText("录制1"), "录制")
        XCTAssertNotEqual(normalizedVisualText("2个动作•約1.0秒"), "1个动作•约1.0秒")
    }
}
