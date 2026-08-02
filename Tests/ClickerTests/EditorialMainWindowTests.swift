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
                .tint(.blue)
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
        NSApplication.shared.activate()
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
        XCTAssertTrue(window.makeFirstResponder(sidebarList))
        let selectedRow = try XCTUnwrap(
            sidebarList.rowView(atRow: sidebarList.selectedRow, makeIfNecessary: false),
            "The selected script row must remain a real outline row"
        )
        selectedRow.isEmphasized = true
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
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
        let headerBounds = CGRect(
            x: sidebarFrame.maxX,
            y: 0,
            width: size.width - sidebarFrame.maxX,
            height: actionListFrame.minY
        )
        let headerTitle = try recognizedFrame(
            containing: "录制1",
            in: recognizedText,
            region: headerBounds,
            requiresExactMatch: true
        )
        let headerMetadata = try XCTUnwrap(
            recognizedText.first { match in
                let normalized = match.text.replacingOccurrences(of: " ", with: "")
                return normalized.contains("1个动作")
                    && normalized.contains("约1.0秒")
                    && headerBounds.contains(match.frame)
            }?.frame,
            "The complete detail metadata must remain inside the measured header: \(recognizedText)"
        )
        XCTAssertTrue(headerBounds.contains(headerTitle))
        XCTAssertTrue(headerBounds.contains(headerMetadata))
        for expected in ["录制", "回放", "重复", "无限", "间隔"] {
            _ = try recognizedFrame(containing: expected, in: recognizedText, region: headerBounds)
        }

        let recordText = try recognizedFrame(
            containing: "录制",
            in: recognizedText,
            region: headerBounds,
            requiresExactMatch: true
        )
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
                within: playbackText
                    .insetBy(dx: -24, dy: -14)
                    .intersection(headerBounds),
                logicalSize: hosting.bounds.size
            ),
            "The playback action must retain a complete visible neutral fill"
        )
        for (name, bounds, label) in [
            ("record", recordBounds, recordText),
            ("playback", playbackBounds, playbackText),
        ] {
            XCTAssertTrue((36 ... 44).contains(bounds.height), "\(name) height: \(bounds)")
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

        let selectedRowFrame = hosting.convert(selectedRow.bounds, from: selectedRow)
        let selectionColor = ClickerVisualTheme.resolvedColor(for: .selection, appearance: appearance)
        let neutralFraction = pixelFraction(
            in: bitmap,
            within: selectedRowFrame,
            logicalSize: hosting.bounds.size
        ) { color in
            abs(color.redComponent - selectionColor.redComponent) <= 0.04
                && abs(color.greenComponent - selectionColor.greenComponent) <= 0.04
                && abs(color.blueComponent - selectionColor.blueComponent) <= 0.04
        }
        let blueFraction = pixelFraction(
            in: bitmap,
            within: selectedRowFrame,
            logicalSize: hosting.bounds.size
        ) { color in
            color.blueComponent - color.redComponent > 0.08
                && color.blueComponent - color.greenComponent > 0.04
                && color.blueComponent > 0.45
        }
        XCTAssertGreaterThan(
            neutralFraction,
            0.5,
            "The blue-tinted selected row must remain mainly neutral: \(neutralFraction)"
        )
        XCTAssertLessThan(
            blueFraction,
            0.02,
            "The selected row must reject accent-dominant blue pixels: \(blueFraction)"
        )
    }

    @MainActor
    func testExtremeFinitePlaybackCompositionUsesRealMainWindowAtMinimumSize() throws {
        let block = ActionBlock.wait(WaitBlock(duration: 1))
        let script = Script(
            name: "边界任务",
            blocks: [block],
            repeatCount: Int.max,
            repeatForever: false,
            repeatInterval: 1.5
        )

        try assertPlayingMainWindow(
            script: script,
            phase: .playing(iteration: Int.max, currentBlockID: block.id),
            expectedProgress: "第\(Int.max)/\(Int.max)轮"
        )
    }

    @MainActor
    func testInfinitePlaybackCompositionUsesRealMainWindowAtMinimumSize() throws {
        let block = ActionBlock.wait(WaitBlock(duration: 1))
        let script = Script(
            name: "定时任务",
            blocks: [block, .wait(WaitBlock(duration: 0.5))],
            repeatCount: 3,
            repeatForever: true,
            repeatInterval: 1.5
        )

        try assertPlayingMainWindow(
            script: script,
            phase: .playing(iteration: 2, currentBlockID: block.id),
            expectedProgress: "第2轮"
        )
    }

    @MainActor
    private func assertPlayingMainWindow(
        script: Script,
        phase: AppPhase,
        expectedProgress: String
    ) throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(store: ScriptStore(directory: directory))
        state.hasPermission = true
        state.scripts = [script, Script(name: "备用任务", blocks: [.wait(WaitBlock(duration: 0.25))])]
        state.selectedScriptID = script.id
        state.phase = phase

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
        let splitView = try XCTUnwrap(renderedViews.compactMap { $0 as? NSSplitView }.first)
        XCTAssertGreaterThanOrEqual(splitView.subviews.count, 2)
        let outlines = renderedViews.compactMap { $0 as? NSOutlineView }
        let sidebarList = try XCTUnwrap(
            outlines.first { $0.selectedRow >= 0 },
            "The real selected sidebar outline must remain hosted: \(outlines)"
        )
        let actionList = try XCTUnwrap(
            outlines.first { $0 !== sidebarList },
            "The real action outline must remain hosted: \(outlines)"
        )
        let sidebarPane = try XCTUnwrap(
            splitView.subviews.first { sidebarList.isDescendant(of: $0) },
            "The sidebar outline must remain inside a split pane"
        )
        let detailPane = try XCTUnwrap(
            splitView.subviews.first { actionList.isDescendant(of: $0) },
            "The action outline must remain inside a split pane"
        )
        let sidebarFrame = hosting.convert(sidebarPane.bounds, from: sidebarPane)
        let detailFrame = hosting.convert(detailPane.bounds, from: detailPane)
        XCTAssertTrue((210 ... 250).contains(sidebarFrame.width), "Sidebar: \(sidebarFrame)")
        XCTAssertTrue(hosting.bounds.contains(sidebarFrame))
        XCTAssertTrue(hosting.bounds.contains(detailFrame), "Detail escaped viewport: \(detailFrame)")
        let actionListFrame = hosting.convert(actionList.bounds, from: actionList)
        XCTAssertTrue(detailFrame.contains(actionListFrame), "Action list escaped detail: \(actionListFrame)")
        XCTAssertLessThanOrEqual(actionListFrame.minY - detailFrame.minY, 152)
        let headerBounds = CGRect(
            x: detailFrame.minX,
            y: detailFrame.minY,
            width: detailFrame.width,
            height: actionListFrame.minY - detailFrame.minY
        )
        XCTAssertTrue((96 ... 104).contains(headerBounds.height), "Header: \(headerBounds)")

        let bitmap = try bitmap(for: hosting)
        let recognizedText = try recognizedTextFrames(
            in: bitmap,
            logicalSize: hosting.bounds.size
        )
        let title = try recognizedFrame(
            containing: script.name.replacingOccurrences(of: " ", with: ""),
            in: recognizedText,
            region: headerBounds,
            requiresExactMatch: true
        )
        XCTAssertTrue(headerBounds.contains(title))
        for expected in ["录制", "回放", "重复", "无限", "间隔"] {
            let frame = try recognizedFrame(
                containing: expected,
                in: recognizedText,
                region: headerBounds
            )
            XCTAssertTrue(headerBounds.contains(frame), "\(expected) escaped header: \(frame)")
        }

        let textFields = renderedViews.compactMap { $0 as? NSTextField }
        for placeholder in ["次数", "秒"] {
            let field = try XCTUnwrap(textFields.first { $0.placeholderString == placeholder })
            let frame = hosting.convert(field.bounds, from: field)
            XCTAssertTrue(headerBounds.contains(frame), "\(placeholder) escaped header: \(frame)")
        }
        let progressRegion = CGRect(
            x: headerBounds.maxX - 200,
            y: headerBounds.minY,
            width: 200,
            height: min(56, headerBounds.height)
        )
        let progressCopy = recognizedText
            .filter { progressRegion.contains($0.frame) }
            .map(\.text)
            .joined()
            .replacingOccurrences(of: " ", with: "")
        let progressGlyphs = progressCopy.filter { "第0123456789/轮".contains($0) }
        XCTAssertEqual(
            progressGlyphs,
            expectedProgress,
            "Full progress must remain OCR-visible in \(progressRegion): \(recognizedText)"
        )

        let settingsButton = try XCTUnwrap(
            renderedViews.compactMap { $0 as? NSButton }.first {
                $0.accessibilityLabel() == "设置"
            }
        )
        XCTAssertTrue(settingsButton.window === window)
        XCTAssertFalse(settingsButton.isHiddenOrHasHiddenAncestor)
        XCTAssertFalse(settingsButton.visibleRect.isEmpty)
    }

    private func recognizedFrame(
        containing expected: String,
        in frames: [(text: String, frame: CGRect)],
        region: CGRect,
        requiresExactMatch: Bool = false
    ) throws -> CGRect {
        try XCTUnwrap(
            frames.first {
                let normalized = $0.text.replacingOccurrences(of: " ", with: "")
                return (requiresExactMatch ? normalized == expected : normalized.contains(expected))
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

    private func pixelFraction(
        in bitmap: NSBitmapImageRep,
        within region: CGRect,
        logicalSize: CGSize,
        matching predicate: (NSColor) -> Bool
    ) -> CGFloat {
        let scaleX = CGFloat(bitmap.pixelsWide) / logicalSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / logicalSize.height
        let minX = max(0, Int((region.minX * scaleX).rounded(.down)))
        let maxX = min(bitmap.pixelsWide, Int((region.maxX * scaleX).rounded(.up)))
        let minY = max(0, Int((region.minY * scaleY).rounded(.down)))
        let maxY = min(bitmap.pixelsHigh, Int((region.maxY * scaleY).rounded(.up)))
        var matches = 0
        var samples = 0

        for y in minY ..< maxY {
            for x in minX ..< maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                samples += 1
                if predicate(color) { matches += 1 }
            }
        }
        return samples == 0 ? 0 : CGFloat(matches) / CGFloat(samples)
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
