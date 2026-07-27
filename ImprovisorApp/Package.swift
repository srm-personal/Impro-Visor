// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Improvisor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ImprovisorEngine", targets: ["ImprovisorEngine"])
    ],
    targets: [
        .target(
            name: "ImprovisorEngine",
            path: "Sources/ImprovisorEngine"
        ),
        .testTarget(
            name: "ImprovisorEngineTests",
            dependencies: ["ImprovisorEngine"],
            path: "Tests/ImprovisorEngineTests"
        )
    ]
)
