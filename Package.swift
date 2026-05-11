// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Murmur",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MurmurCore", targets: ["MurmurCore"]),
        .executable(name: "MurmurMac", targets: ["MurmurMac"]),
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
        .executableTarget(
            name: "MurmurMac",
            dependencies: ["MurmurCore"]
        ),
        .testTarget(
            name: "MurmurCoreTests",
            dependencies: ["MurmurCore"]
        ),
    ]
)
