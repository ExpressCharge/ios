// swift-tools-version: 6.3
//
// ExpresScan — pure-Swift libraries (Wave 1 / Track E-pkg).
//
// These four products contain everything that does not depend on
// UIKit/SwiftUI/CoreNFC, so they can be built and unit-tested via SwiftPM
// on any macOS host (no Xcode required). The SwiftUI app target lives in
// the separate `App/` source tree shipped by tracks E-app-skel and
// E-app-wire and is built via xcodegen on a developer machine.
//
// Banned imports anywhere in `Sources/` (verified by a CI grep guard):
//   UIKit, SwiftUI, CoreNFC, UserNotifications, WatchKit, AppKit.
//
import PackageDescription

let package = Package(
    name: "ExpresScanCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v26),
    ],
    products: [
        .library(name: "Models", targets: ["Models"]),
        .library(name: "Crypto", targets: ["Crypto"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "AuthCore", targets: ["AuthCore"]),
        .library(name: "Capabilities", targets: ["Capabilities"]),
        .library(name: "DeviceSync", targets: ["DeviceSync"]),
    ],
    targets: [
        // MARK: - Library targets
        //
        // No special flags needed — these compile cleanly with stock
        // SwiftPM. Test targets carry their own unsafeFlags below for
        // the standalone-CLT case. See README.md for the
        // `scripts/swift-test.sh` wrapper or the
        // `--toolset scripts/clt-toolset.json` flag.

        .target(
            name: "Models",
            path: "Sources/Models"
        ),
        .target(
            name: "Crypto",
            path: "Sources/Crypto"
        ),
        .target(
            name: "Networking",
            dependencies: ["Models"],
            path: "Sources/Networking"
        ),
        .target(
            name: "AuthCore",
            path: "Sources/AuthCore"
        ),
        .target(
            name: "Capabilities",
            dependencies: ["Models"],
            path: "Sources/Capabilities"
        ),
        .target(
            name: "DeviceSync",
            dependencies: ["Models", "Networking", "AuthCore"],
            path: "Sources/DeviceSync"
        ),

        // MARK: - Test targets

        // Build settings on test targets:
        //
        // The standalone Swift 6.2.4 toolchain (no full Xcode) ships
        // `Testing.framework` under
        // `/Library/Developer/CommandLineTools/Library/Developer/Frameworks`
        // but SwiftPM does not include it in the framework-search-path
        // automatically for test targets. Adding `-F <path>` (and
        // `-rpath` for the dylib at runtime) makes `import Testing`
        // resolve and the test bundle launch.
        //
        // We also pass `-disable-cross-import-overlays` because the
        // `_Testing_Foundation` cross-import overlay framework that
        // ships with CLT-only Swift has no `.swiftmodule` (it's a
        // stub), which blows up the build when `Foundation` and
        // `Testing` are both imported in a test target.
        //
        // On a machine with full Xcode, the same flags are harmless
        // extras — the path is already on the search list and
        // cross-import is rebuilt.

        .testTarget(
            name: "ModelsTests",
            dependencies: ["Models"],
            path: "Tests/ModelsTests",
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xfrontend", "-disable-cross-import-overlays",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ]
        ),
        .testTarget(
            name: "CryptoTests",
            dependencies: ["Crypto"],
            path: "Tests/CryptoTests",
            resources: [
                .copy("Fixtures/hmac-vectors.json"),
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xfrontend", "-disable-cross-import-overlays",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ]
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: ["Networking", "Models"],
            path: "Tests/NetworkingTests",
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xfrontend", "-disable-cross-import-overlays",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ]
        ),
        .testTarget(
            name: "AuthCoreTests",
            dependencies: ["AuthCore"],
            path: "Tests/AuthCoreTests",
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xfrontend", "-disable-cross-import-overlays",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ]
        ),
        .testTarget(
            name: "CapabilitiesTests",
            dependencies: ["Capabilities", "Models"],
            path: "Tests/CapabilitiesTests",
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xfrontend", "-disable-cross-import-overlays",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ]
        ),
        .testTarget(
            name: "DeviceSyncTests",
            dependencies: ["DeviceSync", "Models", "Networking", "AuthCore"],
            path: "Tests/DeviceSyncTests",
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xfrontend", "-disable-cross-import-overlays",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ]
        ),
    ]
)
