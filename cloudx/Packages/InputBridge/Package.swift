// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InputBridge",
    platforms: [.macOS(.v14), .tvOS(.v26), .iOS(.v17)],
    products: [
        .library(name: "InputBridge", targets: ["InputBridge"])
    ],
    dependencies: [
        .package(path: "../CloudXModels")
    ],
    targets: [
        .target(name: "InputBridge", dependencies: [
            .product(name: "CloudXModels", package: "CloudXModels")
        ]),
        .testTarget(name: "InputBridgeTests", dependencies: ["InputBridge"])
    ]
)
