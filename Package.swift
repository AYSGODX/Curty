// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Curty",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Curty", targets: ["Curty"]),
    ],
    targets: [
        .executableTarget(
            name: "Curty",
            path: "Sources/Curty",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CurtyTests",
            dependencies: ["Curty"],
            path: "Tests/CurtyTests"
        ),
    ]
)
