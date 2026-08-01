import AppKit
import XCTest

final class AppIconAssetTests: XCTestCase {
    func testIconBuilderProducesStandardMacRepresentations() throws {
        let root = repositoryRoot()
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let output = temporaryDirectory.appendingPathComponent("Clicker.icns")
        let buildStatus: Int32
        do {
            buildStatus = try run(
                root.appendingPathComponent("scripts/build-icon.sh").path,
                arguments: [
                root.appendingPathComponent("Resources/AppIcon.svg").path,
                output.path,
                ]
            )
        } catch {
            XCTFail("Could not run the icon builder: \(error)")
            return
        }
        XCTAssertEqual(buildStatus, 0)
        guard buildStatus == 0 else { return }

        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        XCTAssertGreaterThan(attributes[.size] as? UInt64 ?? 0, 0)

        let iconset = temporaryDirectory.appendingPathComponent("Clicker.iconset", isDirectory: true)
        let extractionStatus = try run(
            "/usr/bin/iconutil",
            arguments: ["-c", "iconset", output.path, "-o", iconset.path]
        )
        XCTAssertEqual(extractionStatus, 0)
        guard extractionStatus == 0 else { return }

        let expectedRepresentations = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024),
        ]

        for (name, expectedPixels) in expectedRepresentations {
            let imageURL = iconset.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path), "Missing \(name)")
            let image = try XCTUnwrap(NSImage(contentsOf: imageURL), "Could not load \(name)")
            let representation = try XCTUnwrap(image.representations.first, "No representation in \(name)")
            XCTAssertEqual(representation.pixelsWide, expectedPixels, "Wrong width for \(name)")
            XCTAssertEqual(representation.pixelsHigh, expectedPixels, "Wrong height for \(name)")
        }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func run(_ executable: String, arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
