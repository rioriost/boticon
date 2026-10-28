// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoticonCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "BoticonCore", targets: ["BoticonCore"])],
    targets: [
        .target(name: "BoticonCore"),
        .testTarget(name: "BoticonCoreTests", dependencies: ["BoticonCore"])
    ]
)
