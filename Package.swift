// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lightmark",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lightmark", targets: ["Lightmark"])
    ],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "LightmarkCore"),
        .executableTarget(name: "Lightmark", dependencies: [.product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "LightmarkCoreTests", dependencies: ["LightmarkCore"])
    ]
)
