import AppKit
import ClickerCore
import SwiftUI
import Vision
import XCTest
@testable import Clicker

/// Regression coverage for the actual split window, including the empty library
/// that previously repeated a complete onboarding panel in both columns.
final class LibraryVisualHierarchyTests: XCTestCase {
    @MainActor
    func testLibraryHierarchyInEmptyAndPopulatedWindows() throws {
        _ = NSApplication.shared
        for dark in [false, true] {
            for size in [CGSize(width: 760, height: 480), CGSize(width: 1000, height: 700)] {
                for empty in [true, false] {
                    let directory = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let state = AppState(store: ScriptStore(directory: directory))
                    let script = Script(name: "网页整理", blocks: [.wait(WaitBlock(duration: 1))])
                    state.scripts = empty ? [] : [script, Script(name: "文件归档")]
                    state.selectedScriptID = empty ? nil : script.id
                    state.hasPermission = true
                    let controller = NSHostingController(rootView:
                        MainView()
                            .environmentObject(state)
                            .environment(\.colorScheme, dark ? .dark : .light)
                            .frame(width: size.width, height: size.height)
                    )
                    let host = controller.view
                    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    host.frame = CGRect(origin: .zero, size: size)
                    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                    window.title = "Clicker"
                    window.contentViewController = controller
                    window.makeKeyAndOrderFront(nil)
                    defer { window.orderOut(nil) }
                    settle(host)
                    state.hasPermission = true
                    settle(host)

                    let split = try XCTUnwrap(descendants(host).compactMap { $0 as? NSSplitView }.first)
                    let sidebar = try XCTUnwrap(split.subviews.first)
                    let sidebarFrame = host.convert(sidebar.bounds, from: sidebar)
                    XCTAssertTrue((210...250).contains(sidebarFrame.width))
                    let bitmap = try retinaBitmap(for: host)
                    if let destination = ProcessInfo.processInfo.environment["CLICKER_SNAPSHOT_DIR"] {
                        let output = URL(fileURLWithPath: destination, isDirectory: true)
                        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        try png.write(to: output.appendingPathComponent(
                            "\(dark ? "dark" : "light")-library-\(empty ? "empty" : "populated")-\(Int(size.width))x\(Int(size.height)).png"
                        ))
                    }
                    let text = try recognizedText(in: bitmap, size: host.bounds.size)
                    let sidebarText = text.filter { $0.frame.midX < sidebarFrame.maxX }
                    let scene = "\(dark ? "dark" : "light") / \(size) / \(empty ? "empty" : "populated")"
                    print("Library hierarchy \(scene): \(sidebarText)")
                    XCTAssertFalse(sidebarText.contains { $0.text.lowercased().contains("clicker") },
                                   "The app name already lives in the window title; no large sidebar brand block")
                    let heading = try XCTUnwrap(sidebarText.first { $0.text.contains("脚本库") })
                    XCTAssertLessThan(heading.frame.height, 18, "Library heading must stay at sidebar-label scale")
                    let search = try XCTUnwrap(descendants(host).compactMap { $0 as? NSTextField }.first {
                        $0.placeholderString == "搜索脚本"
                    })
                    let searchFrame = host.convert(search.bounds, from: search)
                    let searchBottom = host.isFlipped ? searchFrame.maxY : host.bounds.maxY - searchFrame.minY
                    XCTAssertLessThan(searchBottom, 85, "Compact heading and search must not form a tall masthead")
                    XCTAssertTrue(host.bounds.contains(searchFrame))

                    if empty {
                        for phrase in ["还没有脚本", "开始录制", "新建空白脚本"] {
                            let matches = text.filter { $0.text.contains(phrase) }
                            XCTAssertEqual(matches.count, 1, "Render \(phrase) once in the whole empty window: \(text)")
                            XCTAssertTrue(matches.allSatisfy { $0.frame.minX > sidebarFrame.maxX },
                                          "Empty-library instructions/actions belong only in the detail pane")
                        }
                        XCTAssertFalse(sidebarText.contains { $0.text.contains("录制") || $0.text.contains("新建") })
                        var recordingCuePixels = 0
                        for y in 0..<bitmap.pixelsHigh {
                            for x in Int(sidebarFrame.maxX * 2)..<bitmap.pixelsWide {
                                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                                if color.redComponent > 0.55,
                                   color.redComponent - color.greenComponent > 0.25,
                                   color.redComponent - color.blueComponent > 0.25 {
                                    recordingCuePixels += 1
                                }
                            }
                        }
                        XCTAssertGreaterThan(recordingCuePixels, 100,
                                             "Empty-library recording must keep its visible original red cue")
                    } else {
                        XCTAssertFalse(text.contains { $0.text.contains("还没有脚本") })
                        let outline = try XCTUnwrap(descendants(sidebar).compactMap { $0 as? NSOutlineView }.first)
                        XCTAssertEqual(outline.numberOfRows, 2, "Both real native script rows must remain present")
                        XCTAssertGreaterThanOrEqual(outline.selectedRow, 0)
                        // Vision reads the visibly correct selected name as
                        // "网页壑理" in dark 760pt windows. Validate visible title
                        // ink in each measured native row, not OCR spelling of
                        // arbitrary fixture names. Empty-state copy stays exact.
                        for row in 0..<outline.numberOfRows {
                            let frame = host.convert(outline.rect(ofRow: row), from: outline)
                            let names = sidebarText.filter {
                                frame.contains($0.frame)
                                    && $0.frame.maxX < sidebarFrame.maxX - 50
                                    && !$0.text.contains("个动作")
                                    && $0.text.count >= 2
                            }
                            XCTAssertFalse(names.isEmpty, "Native row \(row) must visibly render its title: \(scene), \(frame), \(sidebarText)")
                        }
                        XCTAssertTrue(sidebarText.contains { $0.text.contains("新建") }, scene)
                        XCTAssertTrue(sidebarText.contains { $0.text.contains("录制") }, scene)
                    }

                }
            }
        }
    }

    @MainActor
    private func settle(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private func recognizedText(in bitmap: NSBitmapImageRep, size: CGSize) throws -> [(text: String, frame: CGRect)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage), orientation: .up).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return (normalizedVisualText(candidate.string), CGRect(
                x: box.minX * size.width, y: (1 - box.maxY) * size.height,
                width: box.width * size.width, height: box.height * size.height
            ))
        }
    }
}
