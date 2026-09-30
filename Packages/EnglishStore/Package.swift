// swift-tools-version: 5.10
// EnglishStore — SwiftData persistence for the English-learning app.
//
// DARWIN ONLY. SwiftData ships with the Darwin SDKs and has no Linux
// implementation, so this package cannot be built or tested on a Linux runner.
// That is deliberate: `EnglishCore` is the portable engine and is unit-tested
// on Linux in milliseconds; only the thin persistence seam lives here, and it
// is verified by the kill-and-reopen tests in `EnglishStoreTests` on macOS.
//
// The dependency direction is one-way: App -> EnglishStore -> EnglishCore.

import PackageDescription

let package = Package(
    name: "EnglishStore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "EnglishStore", targets: ["EnglishStore"]),
    ],
    dependencies: [
        .package(path: "../EnglishCore"),
    ],
    targets: [
        .target(
            name: "EnglishStore",
            dependencies: [
                .product(name: "EnglishCore", package: "EnglishCore"),
            ]
        ),
        .testTarget(
            name: "EnglishStoreTests",
            dependencies: ["EnglishStore"]
        ),
    ]
)
