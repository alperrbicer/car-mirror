// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CarMirrorPipeline",
    platforms: [.macOS(.v14), .iOS("18.0")],
    products: [.library(name: "MirrorCore", targets: ["MirrorCore"]),
               .library(name: "MirrorMedia", targets: ["MirrorMedia"])],
    targets: [
        .target(name: "MirrorCore", path: "Sources/Core"),
        .target(name: "MirrorMedia", dependencies: ["MirrorCore"], path: "Sources/Media"),
        .testTarget(name: "MirrorCoreTests", dependencies: ["MirrorCore"], path: "Tests/Core"),
        .testTarget(name: "MirrorMediaTests", dependencies: ["MirrorMedia", "MirrorCore"], path: "Tests/Media")
    ]
)
