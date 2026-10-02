import AppKit
import ClickerCore
import XCTest
@testable import Clicker

final class ActionEditorWorkflowTests: XCTestCase {
    func testNewActionsRequireExplicitTargetsInsteadOfExecutableDefaults() throws {
        XCTAssertEqual(Set(AddActionKind.allCases.map(\.rawValue)).count, 7)
        for kind in [AddActionKind.click, .move, .drag, .scroll, .typeText, .shortcut] {
            let draft = ActionEditorDraft(kind: kind)
            XCTAssertNil(draft.original)
            XCTAssertEqual(draft.x, "")
            XCTAssertEqual(draft.y, "")
            XCTAssertEqual(draft.text, "")
            XCTAssertNil(draft.keyCode)
            XCTAssertEqual(draft.shortcutFlags, 0)
            XCTAssertThrowsError(try draft.build(), "\(kind) must require user input before saving")
        }
        XCTAssertEqual(try ActionEditorDraft(kind: .wait).build().duration, 1)
    }

    func testSaveFailureRetainsDraftErrorAndIdentityUntilSuccessfulRetry() throws {
        var draft = ActionEditorDraft(kind: .click)
        draft.x = "-500.5"; draft.y = "80"
        var session = ActionEditorSession(draft: draft)
        let before = session.draft
        var attempts: [ActionBlock] = []
        XCTAssertFalse(session.save(using: { attempts.append($0); return false }, errorMessage: { "磁盘已满" }))
        XCTAssertFalse(session.didSave)
        XCTAssertEqual(session.draft, before)
        XCTAssertEqual(session.saveError, "磁盘已满")
        XCTAssertTrue(session.save(using: { attempts.append($0); return true }, errorMessage: { nil }))
        XCTAssertTrue(session.didSave)
        XCTAssertNil(session.saveError)
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(attempts[0], attempts[1], "Retry must not allocate another action ID or lose input")
        XCTAssertFalse(session.save(using: { _ in XCTFail("A dismissed editor must not save again"); return true }, errorMessage: { nil }))
    }

    func testInvalidVisibleNumericInputNeverSavesLastValidValue() {
        let block = ActionBlock.click(ClickBlock(x: 20, y: 30, button: .left, clickCount: 1))
        for input in ["", "oops", "12junk", "nan", "inf", "1e999"] {
            var session = ActionEditorSession(draft: ActionEditorDraft(block: block))
            session.draft.x = input
            var persistCount = 0
            XCTAssertFalse(session.save(using: { _ in persistCount += 1; return true }, errorMessage: { nil }))
            XCTAssertEqual(persistCount, 0)
            XCTAssertEqual(session.draft.x, input)
            XCTAssertNotNil(session.saveError)
        }
    }

    func testDirtyStateTracksUserEditsAndReversionWithoutMutatingOriginal() {
        let block = ActionBlock.wait(WaitBlock(duration: 1))
        var session = ActionEditorSession(draft: ActionEditorDraft(block: block))
        XCTAssertFalse(session.isDirty)
        session.draft.duration = "2"
        XCTAssertTrue(session.isDirty)
        XCTAssertEqual(session.draft.original, block)
        session.draft.duration = "1.0"
        XCTAssertFalse(session.isDirty)
    }

    func testCancellingDraftHasNoPersistenceStep() {
        let existing = Script(name: "Untouched", blocks: [.wait(WaitBlock(duration: 1))])
        var draft: ActionEditorSession? = ActionEditorSession(draft: ActionEditorDraft(kind: .drag))
        draft?.draft.x = "10"
        draft?.draft.y = "20"
        XCTAssertTrue(draft?.isDirty == true)
        draft = nil
        XCTAssertEqual(existing.blocks.count, 1)
        // There is deliberately no Script/AppState reference in a draft session.
    }

    func testNewDragAndScrollUseExplicitCoordinatesAndPreserveDirection() throws {
        var drag = ActionEditorDraft(kind: .drag)
        drag.x = "-100"; drag.y = "20"; drag.endX = "300"; drag.endY = "-40"
        drag.duration = "2.5"; drag.button = .right
        guard case .drag(let builtDrag) = try drag.build() else { return XCTFail("Expected drag") }
        XCTAssertEqual(builtDrag.button, .right)
        XCTAssertEqual(builtDrag.points.map(\.x), [-100, 300])
        XCTAssertEqual(builtDrag.points.map(\.y), [20, -40])
        XCTAssertEqual(builtDrag.points.map(\.t), [0, 2.5])
        XCTAssertEqual(builtDrag.id, drag.id)

        var scroll = ActionEditorDraft(kind: .scroll)
        scroll.x = "100"; scroll.y = "200"; scroll.scrollDeltaY = "-24"
        guard case .scroll(let builtScroll) = try scroll.build() else { return XCTFail("Expected scroll") }
        XCTAssertEqual(builtScroll.x, 100)
        XCTAssertEqual(builtScroll.y, 200)
        XCTAssertEqual(builtScroll.steps.map(\.dy), [-24])
        XCTAssertEqual(builtScroll.steps.first?.x, 100)
        XCTAssertEqual(builtScroll.steps.first?.y, 200)
    }

    func testNewMoveRequiresBothEndpoints() throws {
        var draft = ActionEditorDraft(kind: .move)
        draft.endX = "600"; draft.endY = "400"
        XCTAssertThrowsError(try draft.build())
        draft.x = "100"; draft.y = "200"
        guard case .move(let move) = try draft.build() else { return XCTFail("Expected move") }
        XCTAssertEqual(move.points.map(\.x), [100, 600])
        XCTAssertEqual(move.points.map(\.y), [200, 400])
    }

    func testUnchangedRecordedActionKeepsAllRawInputFidelity() throws {
        let actions: [ActionBlock] = [
            .click(ClickBlock(x: 10, y: 20, button: .left, clickCount: 1,
                duration: 0.8, upX: 12, upY: 23, upClickCount: 2, downFlags: 2, upFlags: 4)),
            .move(MoveBlock(duration: 1, points: [TrackPoint(t: 0, x: 10, y: 20), TrackPoint(t: 1, x: 30, y: 40)])),
            .drag(DragBlock(button: .right, duration: 1, points: [TrackPoint(t: 0, x: 10, y: 20), TrackPoint(t: 1, x: 30, y: 40)])),
            .scroll(ScrollBlock(x: 10, y: 20, duration: 0.5, steps: [ScrollStep(t: 0.5, dx: 5, dy: -8, flags: 2, ordinal: 6)])),
            .typeText(TypeTextBlock(text: "Recorded", keystrokes: [])),
            .shortcut(ShortcutBlock(keyCode: 96, flags: 4, upFlags: 8, duration: 0.3)),
            .wait(WaitBlock(duration: 3)),
        ]
        for action in actions { XCTAssertEqual(try ActionEditorDraft(block: action).build(), action) }
    }

    func testEditedScrollMovesEachSampleWithoutErasingHorizontalMotionOrTiming() throws {
        let original = ActionBlock.scroll(ScrollBlock(x: 10, y: 20, duration: 1, steps: [
            ScrollStep(t: 0, x: 10, y: 20, dx: 3, dy: -2, flags: 4, ordinal: 5),
            ScrollStep(t: 1, x: 12, y: 24, dx: 5, dy: -6, flags: 8, ordinal: 6),
        ], startOffset: 4))
        var draft = ActionEditorDraft(block: original)
        draft.x = "100"; draft.y = "200"; draft.scrollDeltaY = "-16"
        guard case .scroll(let edited) = try draft.build() else { return XCTFail("Expected scroll") }
        XCTAssertEqual(edited.steps.map(\.x), [100, 102])
        XCTAssertEqual(edited.steps.map(\.y), [200, 204])
        XCTAssertEqual(edited.steps.map(\.dy), [-4, -12])
        XCTAssertEqual(edited.steps.map(\.dx), [3, 5])
        XCTAssertEqual(edited.steps.map(\.t), [0, 1])
        XCTAssertEqual(edited.steps.map(\.ordinal), [5, 6])
        XCTAssertEqual(edited.startOffset, 4)
    }

    func testInvalidDurationCannotSilentlyBecomeZero() {
        for input in ["-1", "nan", "infinity", "1e30", ""] {
            var draft = ActionEditorDraft(kind: .wait)
            draft.duration = input
            XCTAssertThrowsError(try draft.build())
        }
    }

    @MainActor
    func testAddMenuReportsOnlyChosenKindAndIncludesDragAndScroll() {
        var selected: [AddActionKind] = []
        let coordinator = AddActionMenu.Coordinator { selected.append($0) }
        for kind in AddActionKind.allCases {
            let item = NSMenuItem(title: kind.title, action: nil, keyEquivalent: "")
            item.representedObject = kind.rawValue
            coordinator.select(item)
        }
        XCTAssertEqual(selected, AddActionKind.allCases)
        XCTAssertTrue(selected.contains(.drag))
        XCTAssertTrue(selected.contains(.scroll))
    }

    func testDesktopCoordinatesRespectPrimaryOriginAndDisplaysAboveAndLeft() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(DesktopCoordinateSpace.quartzPoint(CGPoint(x: 100, y: 850), primaryFrame: primary), CGPoint(x: 100, y: 50))
        XCTAssertEqual(DesktopCoordinateSpace.quartzPoint(CGPoint(x: -200, y: 1000), primaryFrame: primary), CGPoint(x: -200, y: -100))
        XCTAssertEqual(DesktopCoordinateSpace.quartzFrame(CGRect(x: -1200, y: 0, width: 1200, height: 800), primaryFrame: primary), CGRect(x: -1200, y: 100, width: 1200, height: 800))
        XCTAssertEqual(DesktopCoordinateSpace.quartzFrame(CGRect(x: 0, y: 900, width: 1200, height: 800), primaryFrame: primary), CGRect(x: 0, y: -800, width: 1200, height: 800))
    }

    @MainActor
    func testCoordinatePickerCancellationRestoresWindowAndReturnsNoCoordinateOnce() throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("No desktop screen in this test session") }
        let window = NSWindow(contentRect: CGRect(x: 20, y: 20, width: 200, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        defer { window.close() }
        let picker = CoordinatePickerController()
        var results: [CGPoint?] = []
        picker.pick { results.append($0) }
        XCTAssertTrue(picker.isPicking)
        picker.cancel()
        XCTAssertFalse(picker.isPicking)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results.first!)
        picker.cancel()
        XCTAssertEqual(results.count, 1)
        picker.pick { results.append($0) }
        picker.cancel()
        XCTAssertEqual(results.count, 2, "Starting a fresh picker after cancellation must remain safe")
    }
}
