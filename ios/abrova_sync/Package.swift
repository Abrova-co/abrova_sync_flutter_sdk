// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "abrova_sync",
    platforms: [.iOS("13.0")],
    products: [
        .library(name: "abrova-sync", targets: ["abrova_sync"])
    ],
    dependencies: [
        .package(url: "https://center.abrova.ir/abrova/abrova-sync-ios-sdk.git", from: "0.3.0")
    ],
    targets: [
        .target(
            name: "abrova_sync",
            dependencies: [.product(name: "AbrovaSync", package: "abrova-sync-ios-sdk")]
        )
    ]
)
