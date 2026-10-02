import CoreGraphics
import XCTest
import ClickerCore
@testable import Clicker

@MainActor
final class PlaybackCoordinateValidatorTests: XCTestCase {
    private let displays = [
        CGRect(x: 0, y: 0, width: 1440, height: 900),
        CGRect(x: -1280, y: -200, width: 1280, height: 1024),
        CGRect(x: 2000, y: 0, width: 800, height: 600),
    ]

    func testAcceptsValidNegativeCoordinatesOnSecondaryDisplay() {
        let validator = PlaybackCoordinateValidator(displayBounds: { self.displays })
        let plan = makePlan([
            .mouseMove(x: -1200, y: -100, flags: 0),
            .mouseDown(x: -100, y: 400, button: .left, clickCount: 1, flags: 0),
            .mouseDrag(x: -200, y: 500, button: .left, flags: 0),
            .mouseUp(x: -200, y: 500, button: .left, clickCount: 1, flags: 0),
            .scroll(x: -100, y: 300, dx: 0, dy: 10, flags: 0),
        ])
        XCTAssertNil(validator.failureMessage(for: plan))
    }

    func testRejectsCoordinatesInGapBetweenDisplays() {
        let validator = PlaybackCoordinateValidator(displayBounds: { self.displays })
        XCTAssertNotNil(validator.failureMessage(for: makePlan([.mouseMove(x: 1700, y: 100, flags: 0)])))
    }

    func testRejectsInvalidReleaseLocationBeforePostingMouseDown() {
        let validator = PlaybackCoordinateValidator(displayBounds: { self.displays })
        XCTAssertNotNil(validator.failureMessage(for: makePlan([
            .mouseDown(x: 100, y: 100, button: .left, clickCount: 1, flags: 0),
            .mouseUp(x: 10000, y: 100, button: .left, clickCount: 1, flags: 0),
        ])))
    }

    func testNonfiniteValuesRejectedEvenWithoutDisplayProvider() {
        let validator = PlaybackCoordinateValidator()
        for value in [Double.nan, .infinity, -.infinity] {
            XCTAssertNotNil(validator.failureMessage(for: makePlan([.mouseMove(x: value, y: 10, flags: 0)])))
            XCTAssertNotNil(validator.failureMessage(for: makePlan([.scroll(x: 10, y: value, dx: 0, dy: 1, flags: 0)])))
        }
    }

    func testKeyboardAndWaitPlansDoNotRequireDisplayCoordinates() {
        let validator = PlaybackCoordinateValidator(displayBounds: { [] })
        XCTAssertNil(validator.failureMessage(for: makePlan([.keyDown(keyCode: 4, flags: 0, chars: "")])))
        XCTAssertNil(validator.failureMessage(for: PlaybackPlan(steps: [], duration: 1)))
        XCTAssertNotNil(validator.failureMessage(for: makePlan([.mouseMove(x: 0, y: 0, flags: 0)])))
    }

    private func makePlan(_ actions: [StepAction]) -> PlaybackPlan {
        let id = UUID()
        return PlaybackPlan(steps: actions.enumerated().map {
            PlaybackStep(t: Double($0.offset), action: $0.element, blockID: id)
        }, duration: Double(actions.count))
    }
}
