// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIFootprint",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AIFootprint", targets: ["AIFootprint"]),
    ],
    targets: [
        // What each tool leaves behind and how it's described, with no access to the system, so it
        // can be tested on its own. Folder sizes are measured here too, against throwaway folders.
        .target(name: "FootprintCore"),
        .executableTarget(name: "AIFootprint", dependencies: ["FootprintCore"]),
        .testTarget(name: "FootprintCoreTests", dependencies: ["FootprintCore"]),
        // The app's glue, tested with a made-up Mac and windows that are never shown.
        .testTarget(name: "AIFootprintTests", dependencies: ["AIFootprint", "FootprintCore"]),
    ]
)
