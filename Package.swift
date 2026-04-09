// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeSwitcher",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeSwitcher",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "ClaudeSwitcher",
            exclude: [
                "Info.plist",
                "Resources/AppIcon.png",
                "Resources/AppIcon.icns",
            ],
            resources: [
                .process("Assets.xcassets"),
            ]
        ),
    ]
)
