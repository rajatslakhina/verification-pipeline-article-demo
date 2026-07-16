// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ReviewGateKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ReviewGateKit", targets: ["ReviewGateKit"])
    ],
    targets: [
        .target(name: "ReviewGateKit"),
        .testTarget(name: "ReviewGateKitTests", dependencies: ["ReviewGateKit"])
    ]
)
