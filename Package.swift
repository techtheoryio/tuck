// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tuck",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),  // updates from GitHub releases
    ],
    targets: [
        .target(name: "TuckCore"),
        .executableTarget(
            name: "Tuck",
            dependencies: ["TuckCore", .product(name: "Sparkle", package: "Sparkle")],
            exclude: ["Resources"],  // AppIcon.icns, copied into the .app by scripts/build-app.sh
            // SwiftPM records the deployment target as the SDK version, which makes AppKit fall back to the
            // pre-macOS 26 look. Record the real SDK so the system Liquid Glass design is used.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos", "-Xlinker", "14.0", "-Xlinker", "26.0",
                                         "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]  // Sparkle.framework in the .app
        ),
        .testTarget(name: "TuckCoreTests", dependencies: ["TuckCore"]),
    ]
)
