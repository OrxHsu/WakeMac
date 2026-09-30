// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 OrxHsu

import PackageDescription
let package = Package(name: "WakeMac", platforms: [.macOS(.v15)], products: [
    .executable(name: "WakeMac", targets: ["WakeMac"]),
    .executable(name: "WakeMacPowerHelper", targets: ["WakeMacPowerHelper"])
], targets: [
    .target(name: "WakeMacCore"),
    .target(name: "WakeMacPower"),
    .executableTarget(name: "WakeMac", dependencies: ["WakeMacCore", "WakeMacPower"]),
    .executableTarget(name: "WakeMacPowerHelper", dependencies: ["WakeMacCore", "WakeMacPower"]),
    .testTarget(name: "WakeMacCoreTests", dependencies: ["WakeMacCore"]),
    .testTarget(name: "WakeMacAppTests", dependencies: ["WakeMac", "WakeMacCore"])
], swiftLanguageModes: [.v5])
