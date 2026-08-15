// swift-tools-version: 6.0
//
//  Package.swift
//  HealthPit data model sandbox
//
//  The core data model lives in `Healthpit/Core`. That folder is part of the
//  Xcode app target through the project's synchronized root group, and it is
//  compiled a second time here as a plain SwiftPM target so the model can be
//  tested on the Mac with `swift test` – without a simulator and without
//  HealthKit. Nothing in `Healthpit/Core` may import HealthKit, SwiftUI or
//  UIKit for that reason; provider code that needs HealthKit lives in the app
//  target and talks to the core through the adapter protocol.
//

import PackageDescription

let package = Package(
    name: "HealthPitCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "HealthPitCore", targets: ["HealthPitCore"])
    ],
    targets: [
        .target(name: "HealthPitCore", path: "Healthpit/Core"),
        .testTarget(name: "HealthPitCoreTests",
                    dependencies: ["HealthPitCore"],
                    path: "Tests/HealthPitCoreTests")
    ]
)
