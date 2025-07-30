// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SelectionTap",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "SelectionTap",
            targets: ["SelectionTapExecutable"]
        ),
        .library(
            name: "SelectionTapLib",
            targets: ["SelectionTapLib"]
        ),
    ],
    targets: [
        .target(
            name: "SelectionTapLib",
            dependencies: [],
            path: "Sources/SelectionTapLib",
            sources: ["SelectionTap.swift"]
        ),
        .executableTarget(
            name: "SelectionTapExecutable",
            dependencies: ["SelectionTapLib"],
            path: "Sources/SelectionTapExecutable",
            sources: ["main.swift"]
        ),
        .testTarget(
            name: "SelectionTapTests",
            dependencies: ["SelectionTapLib"],
            path: "Tests"
        ),
    ]
)
