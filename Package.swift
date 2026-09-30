// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lightmark",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lightmark", targets: ["Lightmark"])
    ],
    targets: [
        .target(name: "LightmarkCore"),
        .executableTarget(name: "Lightmark", dependencies: ["LightmarkCore"]),
        .testTarget(name: "LightmarkCoreTests", dependencies: ["LightmarkCore"])
    ]
)
