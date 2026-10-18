// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LidLess",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LidLess", targets: ["LidLess"])],
    targets: [
        .target(name: "LidLessCore"),
        .executableTarget(name: "LidLess", dependencies: ["LidLessCore"]),
        .testTarget(name: "LidLessCoreTests", dependencies: ["LidLessCore"]),
    ]
)
