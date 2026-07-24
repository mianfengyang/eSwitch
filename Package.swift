// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CubeTab",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "CubeTab", targets: ["CubeTab"])
    ],
    targets: [
        .executableTarget(
            name: "CubeTab",
            exclude: ["Resources/Info.plist", "Resources/Assets.xcassets", "CubeTab.entitlements", "Resources/CubeTab.icns"],

            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "CubeTabTests",
            dependencies: ["CubeTab"],
            path: "Tests/CubeTabTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
