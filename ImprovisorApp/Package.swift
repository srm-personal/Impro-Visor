// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Improvisor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ImprovisorEngine", targets: ["ImprovisorEngine"]),
        .executable(name: "improvisor-demo", targets: ["improvisor-demo"])
    ],
    targets: [
        .target(
            name: "ImprovisorEngine",
            path: "Sources/ImprovisorEngine"
        ),
        .executableTarget(
            name: "improvisor-demo",
            dependencies: ["ImprovisorEngine"],
            path: "Sources/improvisor-demo"
        ),
        .testTarget(
            name: "ImprovisorEngineTests",
            dependencies: ["ImprovisorEngine"],
            path: "Tests/ImprovisorEngineTests"
        )
    ]
)
