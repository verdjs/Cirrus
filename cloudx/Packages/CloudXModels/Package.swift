// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CloudXModels",
    platforms: [
        .macOS(.v14),
        .tvOS(.v26),
        .iOS(.v17)
    ],
    products: [
        .library(name: "CloudXModels", targets: ["CloudXModels"])
    ],
    targets: [
        .target(name: "CloudXModels"),
        .testTarget(name: "CloudXModelsTests", dependencies: ["CloudXModels"])
    ]
)
