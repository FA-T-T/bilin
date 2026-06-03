// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "BilinMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BilinMac", targets: ["BilinMacApp"]),
        .library(name: "BilinReaderKit", targets: ["BilinReaderKit"]),
        .library(name: "BilinRenderKit", targets: ["BilinRenderKit"]),
        .library(name: "BilinStore", targets: ["BilinStore"])
    ],
    targets: [
        .executableTarget(
            name: "BilinMacApp",
            dependencies: [
                "BilinReaderKit",
                "BilinRenderKit",
                "BilinStore"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(name: "BilinReaderKit"),
        .target(name: "BilinRenderKit"),
        .target(
            name: "BilinStore",
            dependencies: ["BilinReaderKit"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "BilinRenderKitTests",
            dependencies: ["BilinRenderKit"]
        ),
        .testTarget(
            name: "BilinReaderKitTests",
            dependencies: ["BilinReaderKit"],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "BilinStoreTests",
            dependencies: [
                "BilinReaderKit",
                "BilinStore"
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
