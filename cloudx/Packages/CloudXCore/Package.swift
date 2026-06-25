// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CloudXCore",
    platforms: [.macOS(.v14), .tvOS(.v26), .iOS(.v17)],
    products: [
        .library(name: "CloudXCore", targets: ["CloudXCore"])
    ],
    dependencies: [
        .package(path: "../CloudXModels"),
        .package(path: "../XCloudAPI"),
        .package(path: "../StreamingCore"),
        .package(path: "../DiagnosticsKit"),
        .package(path: "../InputBridge"),
        .package(path: "../VideoRenderingKit")
    ],
    targets: [
        .target(name: "CloudXCore", dependencies: [
            .product(name: "CloudXModels", package: "CloudXModels"),
            .product(name: "XCloudAPI", package: "XCloudAPI"),
            .product(name: "StreamingCore", package: "StreamingCore"),
            .product(name: "DiagnosticsKit", package: "DiagnosticsKit"),
            .product(name: "InputBridge", package: "InputBridge"),
            .product(name: "VideoRenderingKit", package: "VideoRenderingKit")
        ]),
        .testTarget(
            name: "CloudXCoreTests",
            dependencies: [
                "CloudXCore",
                .product(name: "XCloudAPI", package: "XCloudAPI")
            ]
        )
    ]
)
