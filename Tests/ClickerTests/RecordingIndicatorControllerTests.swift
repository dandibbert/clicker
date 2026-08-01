import CoreGraphics
import XCTest
@testable import Clicker

@MainActor
final class RecordingIndicatorControllerTests: XCTestCase {
    private let mainFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let sideFrame = CGRect(x: 1440, y: 0, width: 1024, height: 768)

    func testShowCreatesOneNonInteractivePanelPerScreenAndMainScreenGetsHint() {
        let screens = [
            ScreenDescriptor(id: "main", frame: mainFrame, isMain: true, safeAreaTop: 48),
            ScreenDescriptor(id: "side", frame: sideFrame, isMain: false, safeAreaTop: 24)
        ]
        let panels = PanelSpy.factory()
        let controller = RecordingIndicatorController(screens: { screens }, makePanel: panels.make)

        controller.show(shortcut: .defaultValue)

        XCTAssertEqual(panels.created.map(\.descriptor.id), ["main", "side"])
        XCTAssertEqual(panels.created.map(\.showsHint), [true, false])
        XCTAssertEqual(panels.created.map(\.hintTopPadding), [76, 0])
        XCTAssertEqual(panels.created.map(\.ignoresMouseEvents), [true, true])
        XCTAssertEqual(panels.created.map(\.becomesKey), [false, false])
        XCTAssertEqual(panels.created.map(\.orderFrontCount), [1, 1])
    }

    func testCloseOrdersOutEveryPanelOnceAndCanRepeat() {
        let screens = [
            ScreenDescriptor(id: "main", frame: mainFrame, isMain: true, safeAreaTop: 48),
            ScreenDescriptor(id: "side", frame: sideFrame, isMain: false, safeAreaTop: 24)
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
    let configuration: RecordingIndicatorPanelConfiguration
    var showsHint: Bool { configuration.showsHint }
    var hintTopPadding: CGFloat { configuration.hintTopPadding }
    var ignoresMouseEvents: Bool { configuration.ignoresMouseEvents }
    var becomesKey: Bool { configuration.becomesKey }
    private(set) var orderFrontCount = 0
    private(set) var orderOutCount = 0

    init(descriptor: ScreenDescriptor, configuration: RecordingIndicatorPanelConfiguration) {
        self.descriptor = descriptor
        self.configuration = configuration
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
            configuration: RecordingIndicatorPanelConfiguration,
            shortcut _: RecordingStopShortcut
        ) -> RecordingIndicatorPanel {
            let panel = PanelSpy(descriptor: descriptor, configuration: configuration)
            created.append(panel)
            return panel
        }
    }

    static func factory() -> Factory {
        Factory()
    }
}
