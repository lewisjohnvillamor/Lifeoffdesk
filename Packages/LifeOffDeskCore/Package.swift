// swift-tools-version:5.9
import PackageDescription

// Platform-independent logic for Life Off Desk: GPS filtering, walk sessions,
// exploration, persistence, AI output validation and deterministic place search.
// No UIKit/CoreLocation imports, so it builds and tests on Linux as well as iOS.
let package = Package(
    name: "LifeOffDeskCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LifeOffDeskCore", targets: ["LifeOffDeskCore"]),
    ],
    targets: [
        .target(name: "LifeOffDeskCore"),
        .testTarget(name: "LifeOffDeskCoreTests", dependencies: ["LifeOffDeskCore"]),
    ]
)
