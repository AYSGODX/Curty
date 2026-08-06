// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Curty",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Curty", targets: ["Curty"]),
    ],
    targets: [
        .target(
            name: "CurtyShared",
            path: "Sources/CurtyShared",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Curty",
            dependencies: ["CurtyShared"],
            path: "Sources/Curty",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CurtyTests",
            dependencies: ["Curty", "CurtyShared"],
            path: "Tests/CurtyTests"
        ),
    ]
)
