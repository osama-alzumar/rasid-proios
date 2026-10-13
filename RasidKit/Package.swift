// swift-tools-version:5.9
import PackageDescription

// Platform-independent core of the Rasid app: API models, reward rules and the
// offline store/sync engine. Kept free of UIKit/SwiftUI so `swift test` runs
// on Linux as well as on macOS CI.
let package = Package(
    name: "RasidKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RasidKit", targets: ["RasidKit"]),
    ],
    targets: [
        .target(name: "RasidKit"),
        .testTarget(name: "RasidKitTests", dependencies: ["RasidKit"]),
    ]
)
