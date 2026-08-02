import AppKit
import ClickerCore
import SwiftUI
import Vision
import XCTest
@testable import Clicker

final class EditorialMainWindowTests: XCTestCase {
    @MainActor
    func testApprovedMainWindowCompositionAtMinimumSize() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let state = AppState(store: ScriptStore(directory: directory))
        let selected = Script(
            name: "录制 1",
            blocks: [.wait(WaitBlock(duration: 1))],
            repeatCount: 3,
            repeatForever: false,
            repeatInterval: 1.5
        )
        let second = Script(name: "录制 2", blocks: [.wait(WaitBlock(duration: 0.5))])
        state.hasPermission = true
        state.scripts = [selected, second]
        state.selectedScriptID = selected.id

        let size = CGSize(width: 760, height: 480)
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let hostingController = NSHostingController(
            rootView: MainView()
                .environmentObject(state)
                .environment(\.colorScheme, .light)
                .frame(width: size.width, height: size.height)
        )
        let hosting = hostingController.view
        hosting.appearance = appearance
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.contentViewController = hostingController
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))

        let renderedViews = descendants(of: window.contentView?.superview ?? hosting)
        let splitView = try XCTUnwrap(
            renderedViews.compactMap { $0 as? NSSplitView }.first,
            "The real MainView must retain its native split-view composition"
        )
        let outlines = renderedViews.compactMap { $0 as? NSOutlineView }
        let sidebarList = try XCTUnwrap(
            outlines.first { outline in
                splitView.subviews.first.map { outline.isDescendant(of: $0) } == true
            },
            "The script library must remain a real outline view inside the sidebar"
        )
        let actionList = try XCTUnwrap(
            outlines.first { $0 !== sidebarList },
            "The selected script must retain its real action outline view"
        )
        let sidebarFrame = hosting.convert(splitView.subviews[0].bounds, from: splitView.subviews[0])
        XCTAssertTrue(
            (210 ... 250).contains(sidebarFrame.width),
            "The editorial sidebar width is \(sidebarFrame.width)pt"
        )

        let actionListFrame = hosting.convert(actionList.bounds, from: actionList)
        XCTAssertLessThanOrEqual(
            actionListFrame.minY,
            152,
            "Action content begins \(actionListFrame.minY)pt from the top of the viewport"
        )
        let bitmap = try bitmap(for: hosting)
        let recognizedText = try recognizedTextFrames(in: bitmap, logicalSize: hosting.bounds.size)
        let normalizedCopy = recognizedText
            .map(\.text)
            .joined()
            .replacingOccurrences(of: " ", with: "")
        for expected in ["录制1", "个动作", "约1.0秒", "录制", "回放", "重复", "无限", "间隔"] {
            XCTAssertTrue(
                normalizedCopy.contains(expected),
                "The 760×480 MainView must render \(expected): \(normalizedCopy)"
            )
        }

        let headerBounds = CGRect(
            x: sidebarFrame.maxX,
            y: 0,
            width: size.width - sidebarFrame.maxX,
            height: actionListFrame.minY
        )
        let recordText = try recognizedFrame(containing: "录制", in: recognizedText, region: headerBounds)
        let playbackText = try recognizedFrame(containing: "回放", in: recognizedText, region: headerBounds)
        let midpoint = (recordText.maxX + playbackText.minX) / 2
        let recordBounds = try XCTUnwrap(
            visibleRecordCueBounds(
                in: bitmap,
                within: CGRect(
                    x: sidebarFrame.maxX,
                    y: 0,
                    width: midpoint - sidebarFrame.maxX,
                    height: headerBounds.height
                ),
                logicalSize: hosting.bounds.size
            ),
            "The record action must retain a complete visible recording cue"
        )
        let playbackBounds = try XCTUnwrap(
            visibleColorBounds(
                in: bitmap,
                near: ClickerVisualTheme.resolvedColor(for: .playbackFill, appearance: appearance),
                tolerance: 0.08,
                within: CGRect(
                    x: midpoint,
                    y: 0,
                    width: size.width - midpoint,
                    height: headerBounds.height
                ),
                logicalSize: hosting.bounds.size
            ),
            "The playback action must retain a complete visible neutral fill"
        )
        for (name, bounds, label) in [
            ("record", recordBounds, recordText),
            ("playback", playbackBounds, playbackText),
        ] {
            XCTAssertTrue((36 ... 40).contains(bounds.height), "\(name) height: \(bounds)")
            XCTAssertTrue(bounds.contains(label), "\(name) label escaped its visible boundary")
            XCTAssertTrue(hosting.bounds.contains(bounds), "\(name) escaped the viewport")
        }

        let textFields = renderedViews.compactMap { $0 as? NSTextField }
        for placeholder in ["次数", "秒"] {
            let field = try XCTUnwrap(
                textFields.first { $0.placeholderString == placeholder },
                "The real \(placeholder) text field must remain hosted"
            )
            let frame = hosting.convert(field.bounds, from: field)
            XCTAssertTrue(
                hosting.bounds.contains(frame),
                "The \(placeholder) text field escaped the viewport: \(frame)"
            )
        }
        let settingsButton = try XCTUnwrap(
            renderedViews.compactMap { $0 as? NSButton }.first {
                $0.accessibilityLabel() == "设置"
            },
            "The gear settings button must remain hosted"
        )
        XCTAssertTrue(settingsButton.window === window)
        XCTAssertFalse(settingsButton.isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(settingsButton.visibleRect.isEmpty)

        let selectedRow = try XCTUnwrap(
            sidebarList.rowView(atRow: sidebarList.selectedRow, makeIfNecessary: false),
            "The selected script row must remain a real outline row"
        )
        let selectedRowFrame = hosting.convert(selectedRow.bounds, from: selectedRow)
        XCTAssertNotNil(
            visibleColorBounds(
                in: bitmap,
                near: ClickerVisualTheme.resolvedColor(for: .selection, appearance: appearance),
                tolerance: 0.04,
                within: selectedRowFrame,
                logicalSize: hosting.bounds.size
            ),
            "The selected script must use the approved neutral selection surface"
        )
    }

    private func recognizedFrame(
        containing expected: String,
        in frames: [(text: String, frame: CGRect)],
        region: CGRect
    ) throws -> CGRect {
        try XCTUnwrap(
            frames.first {
                let normalized = $0.text.replacingOccurrences(of: " ", with: "")
                return (normalized == expected || (expected == "回放" && normalized.contains(expected)))
                    && region.contains($0.frame)
            }?.frame,
            "Expected OCR text \(expected) inside \(region): \(frames)"
        )
    }

    @MainActor
    private func descendants(of root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @MainActor
    private func bitmap(for hosting: NSView) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    private func recognizedTextFrames(
        in bitmap: NSBitmapImageRep,
        logicalSize: CGSize
    ) throws -> [(text: String, frame: CGRect)] {
        let image = try XCTUnwrap(bitmap.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return (
                text: candidate.string,
                frame: CGRect(
                    x: box.minX * logicalSize.width,
                    y: (1 - box.maxY) * logicalSize.height,
                    width: box.width * logicalSize.width,
                    height: box.height * logicalSize.height
                )
            )
        }
    }

    private func visibleColorBounds(
        in bitmap: NSBitmapImageRep,
        near target: NSColor,
        tolerance: CGFloat,
        within region: CGRect,
        logicalSize: CGSize
    ) -> CGRect? {
        colorBounds(in: bitmap, within: region, logicalSize: logicalSize) { color in
            guard let target = target.usingColorSpace(.sRGB) else { return false }
            return abs(color.redComponent - target.redComponent) <= tolerance
                && abs(color.greenComponent - target.greenComponent) <= tolerance
                && abs(color.blueComponent - target.blueComponent) <= tolerance
        }
    }

    private func visibleRecordCueBounds(
        in bitmap: NSBitmapImageRep,
        within region: CGRect,
        logicalSize: CGSize
    ) -> CGRect? {
        colorBounds(in: bitmap, within: region, logicalSize: logicalSize) { color in
            color.redComponent - color.greenComponent > 0.08
                && color.redComponent - color.blueComponent > 0.08
        }
    }

    private func colorBounds(
        in bitmap: NSBitmapImageRep,
        within region: CGRect,
        logicalSize: CGSize,
        matching predicate: (NSColor) -> Bool
    ) -> CGRect? {
        let scaleX = CGFloat(bitmap.pixelsWide) / logicalSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / logicalSize.height
        let minX = max(0, Int((region.minX * scaleX).rounded(.down)))
        let maxX = min(bitmap.pixelsWide, Int((region.maxX * scaleX).rounded(.up)))
        let minY = max(0, Int((region.minY * scaleY).rounded(.down)))
        let maxY = min(bitmap.pixelsHigh, Int((region.maxY * scaleY).rounded(.up)))
        var matchedMinX = bitmap.pixelsWide
        var matchedMaxX = -1
        var matchedMinY = bitmap.pixelsHigh
        var matchedMaxY = -1

        for y in minY ..< maxY {
            for x in minX ..< maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      predicate(color) else { continue }
                matchedMinX = min(matchedMinX, x)
                matchedMaxX = max(matchedMaxX, x)
                matchedMinY = min(matchedMinY, y)
                matchedMaxY = max(matchedMaxY, y)
            }
        }
        guard matchedMaxX >= matchedMinX, matchedMaxY >= matchedMinY else { return nil }
        return CGRect(
            x: CGFloat(matchedMinX) / scaleX,
            y: CGFloat(matchedMinY) / scaleY,
            width: CGFloat(matchedMaxX - matchedMinX + 1) / scaleX,
            height: CGFloat(matchedMaxY - matchedMinY + 1) / scaleY
        )
    }
}
