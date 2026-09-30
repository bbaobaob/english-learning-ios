// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EnglishCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "EnglishCore", targets: ["EnglishCore"])
    ],
    targets: [
        // Foundation ONLY: no SwiftUI, no SwiftData, no AVFoundation, so this
        // package compiles and tests on Linux as well as on Darwin.
        .target(
            name: "EnglishCore",
            resources: [.copy("Resources/content")]
        ),
        .testTarget(
            name: "EnglishCoreTests",
            dependencies: ["EnglishCore"]
        ),
    ]
)
