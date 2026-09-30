import AppKit
import XCTest

/// Use the same 2× raster on Retina laptops and 1× hosted CI displays.
/// Creating a screen-derived bitmap makes pixel sampling and Vision OCR vary by runner.
@MainActor
func retinaBitmap(for view: NSView) throws -> NSBitmapImageRep {
    let size = view.bounds.size
    let bitmap = try XCTUnwrap(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int((size.width * 2).rounded(.up)),
        pixelsHigh: Int((size.height * 2).rounded(.up)),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    bitmap.size = size
    view.cacheDisplay(in: view.bounds, to: bitmap)
    return bitmap
}

/// Vision may return a Traditional glyph even when asked to recognize zh-Hans.
func normalizedVisualText(_ text: String) -> String {
    text.replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "約", with: "约")
}
