// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RefAppWatch",
    platforms: [.watchOS(.v10), .iOS(.v17), .macOS(.v14)],
    products: [.library(name: "RefAppWatchCore", targets: ["RefAppWatchCore"])],
    targets: [
        .target(name: "RefAppWatchCore"),
        .testTarget(name: "RefAppWatchCoreTests", dependencies: ["RefAppWatchCore"]),
    ]
)
