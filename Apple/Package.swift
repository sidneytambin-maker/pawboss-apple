// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PawBossCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [.library(name: "PawBossCore", targets: ["PawBossCore"])],
    targets: [
        .target(name: "PawBossCore", resources: [.process("Resources")]),
        .testTarget(name: "PawBossCoreTests", dependencies: ["PawBossCore"])
    ]
)
