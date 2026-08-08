// swift-tools-version: 6.0
import PackageDescription

// SunnieShared is the single shared local package described in ADR-002.
// It holds platform-neutral domain types, protocol boundaries, content schemas,
// Watch payloads, and pure utilities used by the iPhone app, the Watch app,
// future widgets, and tests. It must not import SwiftUI, SwiftData, or any
// other Apple UI/persistence framework.
let package = Package(
    name: "SunnieShared",
    // iOS and watchOS are what ships. macOS is here because it is what `swift
    // test` builds for when run from the command line on a Mac, and an
    // undeclared platform silently defaults to macOS 10.13 — old enough that
    // `os.Logger` (macOS 11+) does not exist, so every SunnieLog call fails to
    // compile. Nothing is shipped for macOS; this exists so the package can be
    // tested on the machine doing the testing.
    platforms: [
        .iOS(.v18),
        .watchOS(.v11),
        .macOS(.v14)
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
