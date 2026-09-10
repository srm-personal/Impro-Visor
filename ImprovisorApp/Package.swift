// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Improvisor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ImprovisorEngine", targets: ["ImprovisorEngine"]),
        .library(name: "LeadsheetKit", targets: ["LeadsheetKit"]),
        .executable(name: "improvisor-demo", targets: ["improvisor-demo"])
    ],
    targets: [
        // Pure music engine: parsing, model, generators, audio backends.
        .target(
            name: "ImprovisorEngine",
            path: "Sources/ImprovisorEngine"
        ),
        // SwiftUI document/editor layer shared by the Leadsheet Studio app.
        .target(
            name: "LeadsheetKit",
            dependencies: ["ImprovisorEngine"],
            path: "Sources/LeadsheetKit"
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
        ),
        .testTarget(
            name: "LeadsheetKitTests",
            dependencies: ["LeadsheetKit"],
            path: "Tests/LeadsheetKitTests"
        )
    ]
)
