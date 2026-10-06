// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clicker",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClickerCore"),
        .target(
            name: "CVirtualDisplayPrivate",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
            ]
        ),
        .executableTarget(
            name: "Clicker",
            dependencies: ["ClickerCore", "CVirtualDisplayPrivate"]
        ),
        .testTarget(name: "ClickerCoreTests", dependencies: ["ClickerCore"]),
        .testTarget(name: "ClickerTests", dependencies: ["Clicker"]),
    ]
)
