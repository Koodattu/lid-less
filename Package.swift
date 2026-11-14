// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LidLess",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LidLess", targets: ["LidLess"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "LidLessCore"),
        .executableTarget(name: "LidLess", dependencies: ["LidLessCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "LidLessCoreTests", dependencies: ["LidLessCore"]),
        .testTarget(name: "LidLessTests", dependencies: ["LidLess"]),
    ]
)
