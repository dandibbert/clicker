import CoreGraphics
import XCTest
@testable import Clicker

@MainActor
final class RecordingIndicatorControllerTests: XCTestCase {
    private let mainFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let sideFrame = CGRect(x: 1440, y: 0, width: 1024, height: 768)

    func testShowCreatesOnePanelPerScreenAndMainScreenGetsHint() {
        let screens = [
            ScreenDescriptor(id: "main", frame: mainFrame, isMain: true),
            ScreenDescriptor(id: "side", frame: sideFrame, isMain: false)
        ]
        let panels = PanelSpy.factory()
        let controller = RecordingIndicatorController(screens: { screens }, makePanel: panels.make)

        controller.show(shortcut: .defaultValue)

        XCTAssertEqual(panels.created.map(\.descriptor.id), ["main", "side"])
        XCTAssertEqual(panels.created.map(\.showsHint), [true, false])
        XCTAssertEqual(panels.created.map(\.orderFrontCount), [1, 1])
    }

    func testCloseOrdersOutEveryPanelOnceAndCanRepeat() {
        let screens = [
            ScreenDescriptor(id: "main", frame: mainFrame, isMain: true),
            ScreenDescriptor(id: "side", frame: sideFrame, isMain: false)
        ]
        let panels = PanelSpy.factory()
        let controller = RecordingIndicatorController(screens: { screens }, makePanel: panels.make)
        controller.show(shortcut: .defaultValue)

        controller.close()
        controller.close()

        XCTAssertEqual(panels.created.map(\.orderOutCount), [1, 1])
        XCTAssertEqual(controller.panelCount, 0)
    }
}

@MainActor
private final class PanelSpy: RecordingIndicatorPanel {
    let descriptor: ScreenDescriptor
    let showsHint: Bool
    private(set) var orderFrontCount = 0
    private(set) var orderOutCount = 0

    init(descriptor: ScreenDescriptor, showsHint: Bool) {
        self.descriptor = descriptor
        self.showsHint = showsHint
    }

    func orderFrontRegardless() {
        orderFrontCount += 1
    }

    func orderOut() {
        orderOutCount += 1
    }

    @MainActor
    final class Factory {
        private(set) var created: [PanelSpy] = []

        func make(
            descriptor: ScreenDescriptor,
            showsHint: Bool,
            shortcut _: RecordingStopShortcut
        ) -> RecordingIndicatorPanel {
            let panel = PanelSpy(descriptor: descriptor, showsHint: showsHint)
            created.append(panel)
            return panel
        }
    }

    static func factory() -> Factory {
        Factory()
    }
}
