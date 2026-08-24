// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Nimbus",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Nimbus",
            path: "Sources/Nimbus",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "NimbusTests",
            dependencies: ["Nimbus"],
            path: "Tests/NimbusTests"
        )
    ]
)
