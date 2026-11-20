// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Wally",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Wally", targets: ["Wally"]),
    ],
    targets: [
        .executableTarget(
            name: "Wally",
            path: "Sources/Wally",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/AppIcon.svg"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
            ]
        ),
        .testTarget(
            name: "WallyTests",
            path: "Tests/WallyTests"
        ),
    ]
)
