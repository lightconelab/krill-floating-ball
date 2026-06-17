// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TrellisFloatingBall",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "TrellisFloatingBall",
            targets: ["TrellisFloatingBall"]
        )
    ],
    targets: [
        .executableTarget(
            name: "TrellisFloatingBall"
        )
    ]
)
