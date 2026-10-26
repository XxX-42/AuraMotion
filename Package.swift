// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AuraMotion",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AuraMotion", targets: ["AuraMotionApp"]),
        .executable(name: "CursorReplay", targets: ["CursorReplay"]),
        .library(name: "AuraMotionCore", targets: ["AuraMotionCore"])
    ],
    targets: [
        // C11 Lock-free Atomics module for event-tap arbitration
        .target(
            name: "AuraAtomics",
            publicHeadersPath: "include"
        ),
        // Core framework: Vision, Tracking, Interaction, Event Synthesis
        .target(
            name: "AuraMotionCore",
            dependencies: [
                "AuraAtomics"
            ]
        ),
        // App executable: Menu Bar, Floating HUD, Diagnostics UI
        .executableTarget(
            name: "AuraMotionApp",
            dependencies: [
                "AuraMotionCore"
            ]
        ),
        .executableTarget(
            name: "CursorReplay",
            dependencies: ["AuraMotionCore"]
        ),
        // Comprehensive test suite
        .testTarget(
            name: "AuraMotionTests",
            dependencies: [
                "AuraMotionCore",
                "AuraAtomics"
            ],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
