import AppKit
import ClickerCore
import SwiftUI
import Vision
import XCTest
@testable import Clicker

@MainActor
final class HostedScriptDetailFixture {
    let directory: URL
    let state: AppState
    let appearance: NSAppearance
    let hosting: NSHostingView<AnyView>
    let window: NSWindow

    init(
        script: Script,
        size: CGSize,
        phase: AppPhase = .idle,
        appearanceName: NSAppearance.Name = .aqua,
        colorScheme: ColorScheme = .light
    ) throws {
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        state = AppState(store: ScriptStore(directory: directory))
        state.scripts = [script]
        state.selectedScriptID = script.id
        state.phase = phase
        appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
        hosting = NSHostingView(
            rootView: AnyView(
                ScriptDetailView()
                    .environmentObject(state)
                    .environment(\.colorScheme, colorScheme)
                    .frame(width: size.width, height: size.height)
            )
        )
        hosting.appearance = appearance
        hosting.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        settle()
    }

    func settle() {
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    func tearDown() {
        window.orderOut(nil)
        try? FileManager.default.removeItem(at: directory)
    }
}

extension FinalVisualConsumerTests {
    @MainActor
    func renderBitmap<V: View>(
        _ view: V,
        appearance: NSAppearance,
        size: CGSize
    ) throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = appearance
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    @MainActor
    func bitmap(for hosting: NSHostingView<some View>) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    func recognizedTextFrames(
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

    @MainActor
    func nativeControls<V: View>(in hosting: NSHostingView<V>) -> [NSView] {
        var controls: [ObjectIdentifier: NSView] = [:]
        for y in stride(from: 0, through: Int(hosting.bounds.height), by: 4) {
            for x in stride(from: 0, through: Int(hosting.bounds.width), by: 4) {
                guard let view = hosting.hitTest(CGPoint(x: x, y: y)) else { continue }
                controls[ObjectIdentifier(view)] = view
            }
        }
        return Array(controls.values)
    }

    @MainActor
    func descendants(of root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    func controlLabel(_ view: NSView) -> String? {
        if let label = view.accessibilityLabel(), !label.isEmpty { return label }
        if let field = view as? NSTextField { return field.placeholderString }
        if let button = view as? NSButton, !button.title.isEmpty { return button.title }
        return nil
    }

    func nativeButton<V: View>(
        recognizing expectedText: String,
        among buttons: [NSButton],
        recognizedText: [(text: String, frame: CGRect)],
        in hosting: NSHostingView<V>
    ) -> NSButton? {
        buttons.first { button in
            let buttonFrame = hosting.convert(button.bounds, from: button)
            return recognizedText.contains { match in
                match.text.replacingOccurrences(of: " ", with: "").contains(expectedText)
                    && buttonFrame.contains(match.frame)
            }
        }
    }

    func color(
        in bitmap: NSBitmapImageRep,
        xFraction: CGFloat,
        yFraction: CGFloat
    ) throws -> NSColor {
        try color(
            in: bitmap,
            x: min(bitmap.pixelsWide - 1, Int(CGFloat(bitmap.pixelsWide) * xFraction)),
            y: min(bitmap.pixelsHigh - 1, Int(CGFloat(bitmap.pixelsHigh) * yFraction))
        )
    }

    func color(in bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
        try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
    }

    func visibleColorBounds(
        in bitmap: NSBitmapImageRep,
        near target: NSColor,
        tolerance: CGFloat,
        within region: CGRect,
        logicalSize: CGSize
    ) -> CGRect? {
        guard let target = target.usingColorSpace(.sRGB) else { return nil }
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
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                if abs(color.redComponent - target.redComponent) <= tolerance,
                   abs(color.greenComponent - target.greenComponent) <= tolerance,
                   abs(color.blueComponent - target.blueComponent) <= tolerance {
                    matchedMinX = min(matchedMinX, x)
                    matchedMaxX = max(matchedMaxX, x)
                    matchedMinY = min(matchedMinY, y)
                    matchedMaxY = max(matchedMaxY, y)
                }
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

    func visibleRecordCueBounds(
        in bitmap: NSBitmapImageRep,
        within region: CGRect,
        logicalSize: CGSize
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
                      color.redComponent - color.greenComponent > 0.08,
                      color.redComponent - color.blueComponent > 0.08 else {
                    continue
                }
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

    func renderedPixelFraction(
        in bitmap: NSBitmapImageRep,
        logicalSize: CGSize,
        region: CGRect,
        near target: NSColor,
        tolerance: CGFloat
    ) -> CGFloat {
        guard let target = target.usingColorSpace(.sRGB) else { return 0 }
        let scaleX = CGFloat(bitmap.pixelsWide) / logicalSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / logicalSize.height
        let minX = max(0, Int((region.minX * scaleX).rounded(.down)))
        let maxX = min(bitmap.pixelsWide, Int((region.maxX * scaleX).rounded(.up)))
        let minY = max(0, Int((region.minY * scaleY).rounded(.down)))
        let maxY = min(bitmap.pixelsHigh, Int((region.maxY * scaleY).rounded(.up)))
        guard minX < maxX, minY < maxY else { return 0 }
        var matches = 0
        for y in minY ..< maxY {
            for x in minX ..< maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                if abs(color.redComponent - target.redComponent) <= tolerance,
                   abs(color.greenComponent - target.greenComponent) <= tolerance,
                   abs(color.blueComponent - target.blueComponent) <= tolerance {
                    matches += 1
                }
            }
        }
        return CGFloat(matches) / CGFloat((maxX - minX) * (maxY - minY))
    }

    func renderedColorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        guard let lhs = lhs.usingColorSpace(.sRGB),
              let rhs = rhs.usingColorSpace(.sRGB) else { return .infinity }
        return max(
            abs(lhs.redComponent - rhs.redComponent),
            max(
                abs(lhs.greenComponent - rhs.greenComponent),
                abs(lhs.blueComponent - rhs.blueComponent)
            )
        )
    }

    func visibleRoleBounds(
        in bitmap: NSBitmapImageRep,
        logicalSize: CGSize,
        within region: CGRect,
        target: NSColor,
        excluding background: NSColor
    ) -> CGRect? {
        guard let target = target.usingColorSpace(.sRGB),
              let background = background.usingColorSpace(.sRGB) else { return nil }
        let scaleX = CGFloat(bitmap.pixelsWide) / logicalSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / logicalSize.height
        let minX = max(0, Int((region.minX * scaleX).rounded(.down)))
        let maxX = min(bitmap.pixelsWide, Int((region.maxX * scaleX).rounded(.up)))
        let minY = max(0, Int((region.minY * scaleY).rounded(.down)))
        let maxY = min(bitmap.pixelsHigh, Int((region.maxY * scaleY).rounded(.up)))
        var bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int)?

        for y in minY ..< maxY {
            for x in minX ..< maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                let targetDistance = max(
                    abs(color.redComponent - target.redComponent),
                    max(
                        abs(color.greenComponent - target.greenComponent),
                        abs(color.blueComponent - target.blueComponent)
                    )
                )
                let backgroundDistance = max(
                    abs(color.redComponent - background.redComponent),
                    max(
                        abs(color.greenComponent - background.greenComponent),
                        abs(color.blueComponent - background.blueComponent)
                    )
                )
                guard targetDistance < backgroundDistance, targetDistance <= 0.08 else { continue }
                if let current = bounds {
                    bounds = (
                        min(current.minX, x), max(current.maxX, x),
                        min(current.minY, y), max(current.maxY, y)
                    )
                } else {
                    bounds = (x, x, y, y)
                }
            }
        }
        guard let bounds else { return nil }
        return CGRect(
            x: CGFloat(bounds.minX) / scaleX,
            y: CGFloat(bounds.minY) / scaleY,
            width: CGFloat(bounds.maxX - bounds.minX + 1) / scaleX,
            height: CGFloat(bounds.maxY - bounds.minY + 1) / scaleY
        )
    }

    func contrastRatio(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        let first = relativeLuminance(lhs)
        let second = relativeLuminance(rhs)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func relativeLuminance(_ color: NSColor) -> CGFloat {
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent)
            + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
    }
}
