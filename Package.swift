// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SmootherScroll",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SmootherScroll", targets: ["SmootherScroll"])
    ],
    targets: [
        .target(name: "ScrollCore"),
        .executableTarget(
            name: "SmootherScroll",
            dependencies: ["ScrollCore"]
        ),
        .testTarget(
            name: "ScrollCoreTests",
            dependencies: ["ScrollCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
