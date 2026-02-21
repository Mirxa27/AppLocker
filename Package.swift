// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppLocker",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .executable(
            name: "AppLocker",
            targets: ["AppLocker"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppLocker",
            dependencies: [],
            path: "Sources/AppLocker",
            swiftSettings: []
        )
    ]
)
