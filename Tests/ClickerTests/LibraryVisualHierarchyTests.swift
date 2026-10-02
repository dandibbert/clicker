import AppKit
import ClickerCore
import SwiftUI
import Vision
import XCTest
@testable import Clicker

/// Exercise MainView in a real native window. A genuinely empty library is one
/// welcome surface; filtering a populated library must retain the native split.
final class LibraryVisualHierarchyTests: XCTestCase {
    @MainActor
    func testLibraryHierarchyInEmptyAndPopulatedWindows() throws {
        for dark in [false, true] {
            for size in [CGSize(width: 760, height: 480), CGSize(width: 1000, height: 700)] {
                for empty in [true, false] {
                    do {
                        let selected = Script(name: "网页整理", blocks: [.wait(WaitBlock(duration: 1))])
                        let fixture = try HostedLibraryHierarchyFixture(
                            scripts: empty ? [] : [selected, Script(name: "文件归档")],
                            size: size,
                            dark: dark
                        )
                        defer { fixture.tearDown() }
                        let bitmap = try fixture.snapshot(named: empty ? "empty" : "populated")
                        let text = try fixture.recognizedText(in: bitmap)
                        if empty {
                            try fixture.assertEmptyWelcome(text: text)
                            XCTAssertGreaterThan(redCuePixelCount(in: bitmap), 100,
                                                 "The single welcome surface must retain its visible red recording cue")
                        } else {
                            try fixture.assertPopulatedLibrary(expectedRows: 2)
                            let sidebar = try fixture.sidebar()
                            let sidebarFrame = fixture.frame(of: sidebar)
                            let sidebarText = text.filter { $0.frame.midX < sidebarFrame.maxX }
                            XCTAssertFalse(sidebarText.contains { $0.text.lowercased().contains("clicker") },
                                           "The native titlebar already identifies the application")
                            let heading = try XCTUnwrap(sidebarText.first { $0.text.contains("脚本库") })
                            XCTAssertLessThan(heading.frame.height, 18,
                                              "Library heading must stay at sidebar-label scale")
                            let search = try fixture.searchField()
                            XCTAssertLessThan(fixture.frame(of: search).maxY, 85,
                                              "Heading and search must not form a tall masthead")
                            XCTAssertTrue(fixture.host.bounds.contains(fixture.frame(of: search)))
                            XCTAssertFalse(text.contains { $0.text.contains("创建第一个脚本") })

                            let outline = try fixture.sidebarOutline()
                            // Native row identity/selection are authoritative. Vision can
                            // misread arbitrary Chinese fixture names in dark appearance.
                            for row in 0..<outline.numberOfRows {
                                let frame = fixture.frame(outline.rect(ofRow: row), in: outline)
                                let names = sidebarText.filter {
                                    frame.contains($0.frame)
                                        && $0.frame.maxX < sidebarFrame.maxX - 50
                                        && !$0.text.contains("个动作")
                                        && $0.text.count >= 2
                                }
                                XCTAssertFalse(names.isEmpty,
                                               "Native row \(row) must visibly render title ink: \(frame), \(sidebarText)")
                            }
                            XCTAssertTrue(sidebarText.contains { $0.text.contains("新建") })
                            XCTAssertTrue(sidebarText.contains { $0.text.contains("录制") })
                            try assertCompactTwoRowHeader(in: fixture)
                        }
                    } catch {
                        XCTFail("Library hierarchy failed (dark=\(dark), size=\(size), empty=\(empty)): \(error)")
                    }
                }
            }
        }
    }

    @MainActor
    func testEmptyWelcomeWithoutPermissionsKeepsEditingActionsAvailable() throws {
        for dark in [false, true] {
            for size in [CGSize(width: 760, height: 480), CGSize(width: 1000, height: 700)] {
                do {
                    let fixture = try HostedLibraryHierarchyFixture(size: size, dark: dark, hasPermission: false)
                    defer { fixture.tearDown() }
                    let bitmap = try fixture.snapshot(named: "empty-no-permission")
                    let text = try fixture.recognizedText(in: bitmap)
                    try fixture.assertEmptyWelcome(text: text, canRecord: false)
                    let notice = try XCTUnwrap(text.first { $0.text.contains("录制与回放需要权限") })
                    let heading = try XCTUnwrap(text.first { $0.text.contains("创建第一个脚本") })
                    XCTAssertGreaterThan(heading.frame.minY, notice.frame.maxY,
                                         "Permission help must reserve space rather than cover the welcome")
                    XCTAssertTrue(fixture.state.canEditScripts)
                    XCTAssertEqual(fixture.state.phase, .idle)
                    XCTAssertTrue(fixture.state.scripts.isEmpty)
                } catch {
                    XCTFail("Missing-permission welcome failed (dark=\(dark), size=\(size)): \(error)")
                }
            }
        }
    }

    @MainActor
    private func assertCompactTwoRowHeader(in fixture: HostedLibraryHierarchyFixture) throws {
        let split = try fixture.splitView()
        let sidebarList = try fixture.sidebarOutline()
        let actionList = try XCTUnwrap(fixture.descendants(of: split).compactMap { $0 as? NSOutlineView }.first {
            $0 !== sidebarList
        })
        let detail = try XCTUnwrap(split.subviews.first { actionList.isDescendant(of: $0) })
        let detailFrame = fixture.frame(of: detail)
        let actionFrame = fixture.frame(of: actionList)
        let header = CGRect(x: detailFrame.minX, y: detailFrame.minY,
                            width: detailFrame.width, height: actionFrame.minY - detailFrame.minY)
        XCTAssertTrue((96...104).contains(header.height), "Compact header must remain 100pt: \(header)")
        let record = try fixture.action(named: "开始录制")
        let play = try fixture.action(named: "开始回放")
        let recordFrame = fixture.frame(of: record)
        let playFrame = fixture.frame(of: play)
        for frame in [recordFrame, playFrame] {
            XCTAssertTrue(header.contains(frame), "Transport action escaped the header: \(frame)")
            XCTAssertTrue((36...44).contains(frame.height), "Transport action height changed: \(frame)")
        }
        XCTAssertEqual(recordFrame.midY, playFrame.midY, accuracy: 2,
                       "Record and playback share the first header row")
        XCTAssertFalse(recordFrame.intersects(playFrame))
        for placeholder in ["次数", "秒"] {
            let field = try XCTUnwrap(fixture.descendants(of: detail).compactMap { $0 as? NSTextField }.first {
                $0.placeholderString == placeholder
            })
            let frame = fixture.frame(of: field)
            XCTAssertTrue(header.contains(frame), "Repeat setting escaped the header: \(frame)")
            XCTAssertGreaterThanOrEqual(frame.minY, max(recordFrame.maxY, playFrame.maxY),
                                        "Repeat/interval settings belong on the secondary row")
        }
    }

    private func redCuePixelCount(in bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.redComponent > 0.55,
                   color.redComponent - color.greenComponent > 0.25,
                   color.redComponent - color.blueComponent > 0.25 {
                    count += 1
                }
            }
        }
        return count
    }
}

/// Shared only by the library presentation/transition tests. All snapshots come
/// from the AppKit-hosted production view, including the actual native titlebar.
@MainActor
final class HostedLibraryHierarchyFixture {
    let directory: URL
    let state: AppState
    let controller: NSHostingController<AnyView>
    let window: NSWindow
    let dark: Bool
    var host: NSView { controller.view }

    init(scripts: [Script] = [], size: CGSize = CGSize(width: 760, height: 480),
         dark: Bool = false, hasPermission: Bool = true,
         makeState: (@MainActor (ScriptStore) -> AppState)? = nil,
         importPicker: @escaping @MainActor () throws -> ScriptImportCandidate? = { try ScriptTransferPanels.chooseImport() }) throws {
        _ = NSApplication.shared
        self.dark = dark
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ScriptStore(directory: directory)
        for script in scripts { try store.save(script) }
        state = makeState?(store) ?? AppState(store: store)
        state.selectedScriptID = scripts.first?.id
        state.hasPermission = hasPermission
        controller = NSHostingController(rootView: AnyView(
            MainView(importPicker: importPicker)
                .environmentObject(state)
                .environment(\.colorScheme, dark ? .dark : .light)
                .frame(width: size.width, height: size.height)
        ))
        controller.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        controller.view.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(contentRect: controller.view.frame,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Clicker"
        window.appearance = controller.view.appearance
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        settle()
        // MainView refreshes real permissions on activation. Pin the visual
        // scenario afterward. Recording tests inject inert input services.
        state.hasPermission = hasPermission
        settle()
    }

    func tearDown() {
        window.orderOut(nil)
        try? FileManager.default.removeItem(at: directory)
    }

    func settle(until ready: () -> Bool = { true }, timeout: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.05)))
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            if ready() { return }
        } while Date() < deadline
    }

    func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    func splitView() throws -> NSSplitView {
        try XCTUnwrap(descendants(of: host).compactMap { $0 as? NSSplitView }.first,
                      "A populated library must keep the real NavigationSplitView")
    }

    func sidebar() throws -> NSView {
        let outline = try sidebarOutline()
        return try XCTUnwrap(try splitView().subviews.first { outline.isDescendant(of: $0) })
    }

    func sidebarOutline() throws -> NSOutlineView {
        try XCTUnwrap(descendants(of: try splitView()).compactMap { $0 as? NSOutlineView }
            .min { frame(of: $0).minX < frame(of: $1).minX })
    }

    func searchField() throws -> NSTextField {
        try XCTUnwrap(descendants(of: host).compactMap { $0 as? NSTextField }.first {
            $0.placeholderString == "搜索脚本"
        })
    }

    func assertPopulatedLibrary(expectedRows: Int) throws {
        let split = try splitView()
        XCTAssertEqual(descendants(of: host).filter { $0 is NSSplitView }.count, 1)
        // NSSplitView also owns native divider/accessory views. Identify its
        // actual library pane by the outline it hosts, not by subview count.
        XCTAssertTrue(try sidebarOutline().isDescendant(of: split))
        let sidebarFrame = frame(of: try sidebar())
        XCTAssertTrue((210...250).contains(sidebarFrame.width), "Sidebar width: \(sidebarFrame)")
        let outline = try sidebarOutline()
        XCTAssertEqual(outline.numberOfRows, expectedRows)
        if expectedRows > 0 { XCTAssertGreaterThanOrEqual(outline.selectedRow, 0) }
        _ = try searchField()
    }

    func assertEmptyWelcome(text: [(text: String, frame: CGRect)], canRecord: Bool = true) throws {
        XCTAssertTrue(state.scripts.isEmpty)
        XCTAssertFalse(descendants(of: host).contains { $0 is NSSplitView },
                       "A genuinely empty library must be one full-width welcome, not two vacant columns")
        XCTAssertFalse(descendants(of: host).contains { $0 is NSOutlineView })
        XCTAssertFalse(descendants(of: host).compactMap { $0 as? NSTextField }.contains {
            $0.placeholderString == "搜索脚本"
        }, "There is nothing to search before the first script exists")
        for phrase in ["创建第一个脚本", "开始录制", "新建空白脚本", "导入脚本"] {
            XCTAssertEqual(text.filter { $0.text.contains(phrase) }.count, 1,
                           "Render \(phrase) exactly once: \(text)")
        }
        let record = try action(named: "开始录制")
        let blank = try action(named: "新建空白脚本")
        let importAction = try action(named: "导入脚本")
        XCTAssertEqual(record.isAccessibilityEnabled(), canRecord)
        XCTAssertTrue(blank.isAccessibilityEnabled())
        XCTAssertTrue(importAction.isAccessibilityEnabled())
        let frames = [record, blank, importAction].map { frame(of: $0) }
        for frame in frames {
            XCTAssertTrue(host.bounds.contains(frame), "Welcome control escaped the viewport: \(frame)")
            XCTAssertGreaterThan(frame.width, 40)
            XCTAssertTrue((36...44).contains(frame.height), "Welcome control must keep a consistent height: \(frame)")
        }
        for first in frames.indices {
            for second in frames.indices where second > first {
                XCTAssertFalse(frames[first].intersects(frames[second]), "Welcome hit targets overlap")
                XCTAssertEqual(frames[first].height, frames[second].height, accuracy: 2)
            }
        }
    }

    func accessibleActions(in root: NSView? = nil) -> [LibraryAccessibleAction] {
        let root = root ?? host
        var visited = Set<ObjectIdentifier>()
        var actions: [LibraryAccessibleAction] = []
        func visit(_ candidate: Any) {
            guard let object = candidate as? NSObject,
                  visited.insert(ObjectIdentifier(object)).inserted else { return }
            let action: LibraryAccessibleAction
            let children: [Any]
            if let view = candidate as? NSView {
                // NSView's accessibility methods are callable even when the
                // runtime object does not advertise protocol conformance.
                action = LibraryAccessibleAction(view: view)
                children = (view.accessibilityChildren() ?? []) + view.subviews
            } else if let element = candidate as? NSAccessibilityElement {
                action = LibraryAccessibleAction(element: element)
                children = element.accessibilityChildren() ?? []
            } else if let element = candidate as? NSAccessibilityProtocol {
                action = LibraryAccessibleAction(element: element)
                children = element.accessibilityChildren() ?? []
            } else {
                return
            }
            if action.role?.rawValue.lowercased().contains("button") == true,
               !action.accessibilityFrame().isEmpty {
                actions.append(action)
            }
            for child in children { visit(child) }
        }
        visit(root)
        return actions
    }

    func action(named name: String, in root: NSView? = nil) throws -> LibraryAccessibleAction {
        let actions = accessibleActions(in: root)
        var frames = Set<String>()
        let matches = actions.filter { action in
            guard label(of: action) == normalizedVisualText(name) else { return false }
            let rect = action.accessibilityFrame()
            let key = [rect.minX, rect.minY, rect.width, rect.height].map { String(Int($0.rounded())) }.joined(separator: ",")
            return frames.insert(key).inserted
        }
        let diagnostic = descendants(of: root ?? host).map { String(describing: type(of: $0)) }.joined(separator: ", ")
        XCTAssertEqual(matches.count, 1, "One accessible \(name) action expected; actions: \(actions.map { label(of: $0) }); native views: \(diagnostic)")
        return try XCTUnwrap(matches.first, "The \(name) action must be discoverable")
    }

    func label(of element: LibraryAccessibleAction) -> String {
        if let label = element.label, !label.isEmpty { return normalizedVisualText(label) }
        return normalizedVisualText(element.title ?? "")
    }

    func frame(of element: LibraryAccessibleAction) -> CGRect {
        let inWindow = window.convertFromScreen(element.accessibilityFrame())
        return topDown(host.convert(inWindow, from: nil))
    }

    func frame(of view: NSView) -> CGRect { frame(view.bounds, in: view) }

    func frame(_ bounds: CGRect, in view: NSView) -> CGRect {
        topDown(host.convert(bounds, from: view))
    }

    private func topDown(_ frame: CGRect) -> CGRect {
        guard !host.isFlipped else { return frame }
        return CGRect(x: frame.minX, y: host.bounds.maxY - frame.maxY,
                      width: frame.width, height: frame.height)
    }

    @discardableResult
    func snapshot(named name: String) throws -> NSBitmapImageRep {
        settle()
        let bitmap = try retinaBitmap(for: host)
        guard let destination = ProcessInfo.processInfo.environment["CLICKER_SNAPSHOT_DIR"] else { return bitmap }
        let output = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let stem = "\(dark ? "dark" : "light")-library-\(name)-\(Int(host.bounds.width))x\(Int(host.bounds.height))"
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent("\(stem).png"))
        let nativeFrame = try XCTUnwrap(window.contentView?.superview,
                                       "Snapshots require the actual native window frame")
        nativeFrame.layoutSubtreeIfNeeded()
        nativeFrame.displayIfNeeded()
        XCTAssertGreaterThan(nativeFrame.bounds.height, host.bounds.height,
                             "Full-window evidence must include actual native titlebar chrome")
        let fullWindow = try retinaBitmap(for: nativeFrame)
        try XCTUnwrap(fullWindow.representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent("\(stem)-native-window.png"))
        return bitmap
    }

    func snapshotSheet(named name: String) throws {
        let sheet = try XCTUnwrap(window.attachedSheet)
        let frame = try XCTUnwrap(sheet.contentView?.superview)
        frame.layoutSubtreeIfNeeded()
        frame.displayIfNeeded()
        let bitmap = try retinaBitmap(for: frame)
        guard let destination = ProcessInfo.processInfo.environment["CLICKER_SNAPSHOT_DIR"] else { return }
        let output = URL(fileURLWithPath: destination, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fileName = "\(dark ? "dark" : "light")-library-\(name)-native-sheet.png"
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent(fileName))
    }

    func recognizedText(in bitmap: NSBitmapImageRep) throws -> [(text: String, frame: CGRect)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage), orientation: .up).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return (normalizedVisualText(candidate.string), CGRect(
                x: box.minX * host.bounds.width, y: (1 - box.maxY) * host.bounds.height,
                width: box.width * host.bounds.width, height: box.height * host.bounds.height
            ))
        }
    }
}

/// A narrow adapter over real AppKit accessibility methods. Native NSViews and
/// virtual NSAccessibilityElements need not pass the same runtime protocol cast.
@MainActor
struct LibraryAccessibleAction {
    let role: NSAccessibility.Role?
    let label: String?
    let title: String?
    private let enabled: () -> Bool
    private let press: () -> Bool
    private let screenFrame: () -> CGRect

    init(view: NSView) {
        role = view.accessibilityRole()
        label = view.accessibilityLabel()
        title = view.accessibilityTitle()
        enabled = { view.isAccessibilityEnabled() }
        press = { view.accessibilityPerformPress() }
        screenFrame = { view.accessibilityFrame() }
    }

    init(element: NSAccessibilityElement) {
        role = element.accessibilityRole()
        label = element.accessibilityLabel()
        title = element.accessibilityTitle()
        enabled = { element.isAccessibilityEnabled() }
        press = { element.accessibilityPerformPress() }
        screenFrame = { element.accessibilityFrame() }
    }

    init(element: NSAccessibilityProtocol) {
        role = element.accessibilityRole()
        label = element.accessibilityLabel()
        title = element.accessibilityTitle()
        enabled = { element.isAccessibilityEnabled() }
        press = { element.accessibilityPerformPress() }
        screenFrame = { element.accessibilityFrame() }
    }

    func isAccessibilityEnabled() -> Bool { enabled() }
    func accessibilityPerformPress() -> Bool { press() }
    func accessibilityFrame() -> CGRect { screenFrame() }
}
