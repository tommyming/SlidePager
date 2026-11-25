// swift-tools-version:6.0
// SlidePager 1.1.0. The package version is the git tag, not a field here.
import PackageDescription

let package = Package(
    name: "SlidePager",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "SlidePager", targets: ["SlidePager"]),
    ],
    targets: [
        .target(name: "SlidePager"),
        .testTarget(name: "SlidePagerTests", dependencies: ["SlidePager"]),
    ]
)
