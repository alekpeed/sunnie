// swift-tools-version: 6.0
import PackageDescription

// SunnieShared is the single shared local package described in ADR-002.
// It holds platform-neutral domain types, protocol boundaries, content schemas,
// Watch payloads, and pure utilities used by the iPhone app, the Watch app,
// future widgets, and tests. It must not import SwiftUI, SwiftData, or any
// other Apple UI/persistence framework.
let package = Package(
    name: "SunnieShared",
    platforms: [
        .iOS(.v18),
        .watchOS(.v11)
    ],
    products: [
        .library(name: "SunnieShared", targets: ["SunnieShared"])
    ],
    targets: [
        .target(
            name: "SunnieShared",
            resources: [.process("Resources")],
            // The app targets build in Swift 5 language mode (see ADR-010).
            // Keep the package aligned so `Sendable` diagnostics behave identically.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SunnieSharedTests",
            dependencies: ["SunnieShared"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
