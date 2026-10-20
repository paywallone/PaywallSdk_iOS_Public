// swift-tools-version: 5.10
//
// Paywall iOS SDK 1.0.0 (Masterpass iOS SDK 1.7.1 dahil).

import PackageDescription

let package = Package(
    name: "PaywallSDK",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(name: "PaywallSDK", targets: ["PaywallSDK", "Masterpass"]),
    ],
    targets: [
        .binaryTarget(name: "PaywallSDK", path: "PaywallSDK.xcframework"),
        .binaryTarget(name: "Masterpass", path: "Masterpass.xcframework"),
    ]
)
