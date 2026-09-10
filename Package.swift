// swift-tools-version: 6.2
//
// LineaCore — the Foundation-only core of Linea (Domain + Intelligence).
//
// This manifest exists so the core can be built and tested WITHOUT Xcode
// (Linux + Docker, CI). In Xcode the very same files are compiled as part of
// the app target via the synchronized `Linea/` folder; nothing here is
// referenced by Linea.xcodeproj. Keep the settings below in parity with the
// project build settings — change them only together with project.pbxproj.
//
import PackageDescription

/// Mirrors Linea.xcodeproj build settings so isolation/concurrency semantics
/// are identical in both homes of the code.
let xcodeParity: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),                            // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
    .enableUpcomingFeature("MemberImportVisibility"),             // SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),     // ┐
    .enableUpcomingFeature("InferIsolatedConformances"),          // │
    .enableUpcomingFeature("DisableOutwardActorInference"),       // │ SWIFT_APPROACHABLE_CONCURRENCY = YES
    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),  // │
    .enableUpcomingFeature("InferSendableFromCaptures"),          // ┘
]

let package = Package(
    name: "LineaCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "LineaCore", targets: ["LineaCore"]),
    ],
    targets: [
        .target(
            name: "LineaCore",
            path: "Linea/Core",
            swiftSettings: xcodeParity
        ),
        .testTarget(
            name: "LineaCoreTests",
            dependencies: ["LineaCore"],
            path: "Tests/LineaCoreTests",
            swiftSettings: xcodeParity
        ),
    ],
    swiftLanguageModes: [.v5]                                     // SWIFT_VERSION = 5.0
)
