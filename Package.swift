// swift-tools-version:6.0
// SlidePager 1.0.0. The package version is the git tag, not a field here.
import PackageDescription

let package = Package(
    name: "SlidePager",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(name: "SlidePager", targets: ["SlidePager"]),
        .library(name: "SlidePagerDemo", targets: ["SlidePagerDemo"]),
    ],
    targets: [
        .target(name: "SlidePager"),
        .target(
            name: "SlidePagerDemo",
            dependencies: ["SlidePager"],
            path: "Example/SlidePagerDemoApp",
            exclude: ["AppDelegate.swift", "SceneDelegate.swift"]
        ),
        .testTarget(name: "SlidePagerTests", dependencies: ["SlidePager"]),
    ]
)
