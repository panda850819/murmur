// swift-tools-version: 5.10
import PackageDescription

// MurmurCore — shared voice-to-text logic, dep of macOS and (future) iOS apps.
//
// Lives in `Core/` so the root Xcode project (which packages MurmurMac.app
// with Info.plist + entitlements + signing) can reference this package via
// `packages: MurmurCore: { path: Core }` without the self-referential
// XcodeGen wiring bug that fires when the package sits at the project root.

let package = Package(
    name: "MurmurCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MurmurCore", targets: ["MurmurCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", exact: "1.0.0"),
    ],
    targets: [
        .target(
            name: "MurmurCore",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .testTarget(
            name: "MurmurCoreTests",
            dependencies: ["MurmurCore"]
        ),
    ]
)
