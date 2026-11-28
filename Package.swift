// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NanZip",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NanZip", targets: ["NanZip"]),
        .executable(name: "NanZipFinder", targets: ["NanZipFinder"]),
        .executable(name: "NanZipQuickLook", targets: ["NanZipQuickLook"]),
        .executable(name: "NanZipXPCService", targets: ["NanZipXPCService"])
    ],
    targets: [
        .target(
            name: "NanZipCore",
            path: "Sources/NanZipCore"
        ),
        .executableTarget(
            name: "NanZip",
            dependencies: ["NanZipCore"],
            path: "Sources/NanZip"
        ),
        .executableTarget(
            name: "NanZipFinder",
            path: "Sources/NanZipFinder",
            linkerSettings: [
                .linkedFramework("FinderSync")
            ]
        ),
        .executableTarget(
            name: "NanZipQuickLook",
            dependencies: ["NanZipCore"],
            path: "Sources/NanZipQuickLook",
            linkerSettings: [
                .linkedFramework("QuickLookUI"),
                .linkedFramework("Quartz")
            ]
        ),
        .executableTarget(
            name: "NanZipXPCService",
            dependencies: ["NanZipCore"],
            path: "Sources/NanZipXPCService"
        ),
        .testTarget(
            name: "NanZipCoreTests",
            dependencies: ["NanZipCore"],
            path: "Tests/NanZipCoreTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
