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
        .library(name: "BilinWorkspaceKit", targets: ["BilinWorkspaceKit"]),
        .library(name: "BilinRenderKit", targets: ["BilinRenderKit"]),
        .library(name: "BilinImportKit", targets: ["BilinImportKit"]),
        .library(name: "BilinStore", targets: ["BilinStore"])
    ],
    targets: [
        .executableTarget(
            name: "BilinMacApp",
            dependencies: [
                "BilinImportKit",
                "BilinReaderKit",
                "BilinRenderKit",
                "BilinWorkspaceKit",
                "BilinStore"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "BilinReaderKit",
            dependencies: ["BilinWorkspaceKit"]
        ),
        .target(name: "BilinWorkspaceKit"),
        .target(name: "BilinRenderKit"),
        .target(
            name: "BilinImportKit",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
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
            name: "BilinWorkspaceKitTests",
            dependencies: ["BilinWorkspaceKit"]
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
        ),
        .testTarget(
            name: "BilinImportKitTests",
            dependencies: ["BilinImportKit"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "BilinMacAppTests",
            dependencies: [
                "BilinMacApp",
                "BilinRenderKit"
            ]
        )
    ]
)
