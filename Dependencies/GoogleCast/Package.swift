// swift-tools-version: 5.9
import PackageDescription

// Official Google static XCFramework. SwiftPM verifies this exact SDK archive.
let package = Package(
    name: "GoogleCast",
    platforms: [.iOS(.v16)],
    products: [.library(name: "GoogleCast", targets: ["CastDependencies"])],
    dependencies: [.package(url: "https://github.com/google/gtm-session-fetcher.git", exact: "3.5.0")],
    targets: [.target(name: "CastDependencies", dependencies: [
        "GoogleCast", .product(name: "GTMSessionFetcherCore", package: "gtm-session-fetcher")
    ], linkerSettings: [.linkedLibrary("c++"), .linkedLibrary("z")]), .binaryTarget(
        name: "GoogleCast",
        url: "https://dl.google.com/dl/chromecast/sdk/ios/GoogleCastSDK-ios-4.8.6_static.zip",
        checksum: "e1fe7fd6f2bf4b58e830d378fafc435d159bd755f7ee20fd3033aa1ce313cd6e"
    )]
)
