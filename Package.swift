// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "dxl-mac-window-manager",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "DXLSnapCore", targets: ["DXLSnapCore"]),
        .executable(name: "DXLWindowManager", targets: ["DXLWindowManager"]),
    ],
    targets: [
        .target(
            name: "DXLSnapCore",
            path: "Sources/DXLSnapCore"
        ),
        .executableTarget(
            name: "DXLWindowManager",
            dependencies: ["DXLSnapCore"],
            path: "Sources/DXLWindowManager"
        ),
        .testTarget(
            name: "DXLSnapCoreTests",
            dependencies: ["DXLSnapCore"],
            path: "Tests/DXLSnapCoreTests"
        ),
    ]
)
