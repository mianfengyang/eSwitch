// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "eSwitch",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "eSwitch", targets: ["eSwitch"])
    ],
    targets: [
        .executableTarget(
            name: "eSwitch",
            path: "eSwitch",
            exclude: ["Resources/Info.plist", "Resources/Assets.xcassets", "eSwitch.entitlements", "Resources/eSwitch.icns"],

            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "eSwitchTests",
            dependencies: ["eSwitch"],
            path: "Tests/eSwitchTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
