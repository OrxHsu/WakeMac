// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "WakeMac", platforms: [.macOS(.v14)], products: [
    .executable(name: "WakeMac", targets: ["WakeMac"])
], targets: [
    .target(name: "WakeMacCore"),
    .executableTarget(name: "WakeMac", dependencies: ["WakeMacCore"]),
    .testTarget(name: "WakeMacCoreTests", dependencies: ["WakeMacCore"]),
    .testTarget(name: "WakeMacAppTests", dependencies: ["WakeMac", "WakeMacCore"])
], swiftLanguageModes: [.v5])
