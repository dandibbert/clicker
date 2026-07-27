import CoreGraphics
import XCTest
@testable import Clicker
import ClickerCore

@MainActor
final class AppStateRecordingTests: XCTestCase {
    func testTargetIsCapturedBeforeHideAndUIStopSavesTrailingOnlyRecording() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-AppStateTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let recorder = StubEventRecorder(
            capture: RecordingCapture(events: [], duration: 0.2)
        )
        let countdown = ImmediateCountdown()
        let application = StubRecordingApplication(
            targetBundleIdentifier: "com.example.target"
        )
        let state = AppState(
            store: ScriptStore(directory: directory),
            recorder: recorder,
            countdown: countdown,
            application: application
        )
        state.hasPermission = true

        state.toggleRecord(source: .ui)
        await Task.yield()

        XCTAssertEqual(application.calls, ["frontmostApplication", "hide"])
        XCTAssertEqual(state.phase, .recording)

        state.toggleRecord(source: .ui)

        let script = try XCTUnwrap(state.scripts.first)
        XCTAssertTrue(script.blocks.isEmpty)
        XCTAssertEqual(script.trailingDelay, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(script.targetBundleIdentifier, "com.example.target")
    }

    func testMenuBarStopUsesTimestampCutoffBeforeBuildingScript() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-AppStateTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let recorder = StubEventRecorder(
            capture: RecordingCapture(
                events: [
                    RecordedEvent(t: 0.1, kind: .leftDown),
                    RecordedEvent(t: 0.2, kind: .leftUp),
                    RecordedEvent(t: 0.8, kind: .mouseMove),
                ],
                duration: 1
            ),
            cutoff: RecordingCutoff(eventCount: 2, duration: 0.7)
        )
        let state = AppState(
            store: ScriptStore(directory: directory),
            recorder: recorder,
            countdown: ImmediateCountdown(),
            application: StubRecordingApplication(targetBundleIdentifier: nil)
        )
        state.phase = .recording

        let cutoff = try XCTUnwrap(state.establishMenuBarCutoff(at: 9_000))

        XCTAssertEqual(recorder.cutoffTimestamps, [9_000])
        XCTAssertEqual(state.phase, .recording)
        XCTAssertTrue(state.scripts.isEmpty)

        state.stopRecordingFromMenuBar(cutoff: cutoff)

        let script = try XCTUnwrap(state.scripts.first)
        XCTAssertFalse(script.blocks.contains { block in
            if case .move = block { return true }
            return false
        })
        XCTAssertEqual(
            BlockExpander.plan(
                blocks: script.blocks,
                trailingDelay: script.trailingDelay
            ).duration,
            0.7,
            accuracy: 0.000_001
        )
    }
}

private final class StubEventRecorder: EventRecording {
    var onTapFailure: (() -> Void)?
    private let capture: RecordingCapture
    private let cutoffValue: RecordingCutoff
    private(set) var cutoffTimestamps: [CGEventTimestamp] = []

    init(
        capture: RecordingCapture,
        cutoff: RecordingCutoff = RecordingCutoff(eventCount: 0, duration: 0)
    ) {
        self.capture = capture
        cutoffValue = cutoff
    }

    func start() -> Bool { true }
    func stop() -> RecordingCapture { capture }

    func cutoff(at timestamp: CGEventTimestamp) -> RecordingCutoff {
        cutoffTimestamps.append(timestamp)
        return cutoffValue
    }
}

private final class ImmediateCountdown: CountdownPresenting {
    func show(
        seconds _: Int,
        onTick _: @escaping (Int) -> Void,
        onFinish: @escaping () -> Void
    ) {
        onFinish()
    }

    func close() {}
}

private final class StubRecordingApplication: RecordingApplicationControlling {
    private let targetBundleIdentifier: String?
    private(set) var calls: [String] = []

    init(targetBundleIdentifier: String?) {
        self.targetBundleIdentifier = targetBundleIdentifier
    }

    func frontmostApplicationBundleIdentifier() -> String? {
        calls.append("frontmostApplication")
        return targetBundleIdentifier
    }

    func hideClicker() {
        calls.append("hide")
    }

    func restoreClicker() {
        calls.append("restore")
    }
}
