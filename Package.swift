// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AgentLayout",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "AgentLayout",
            targets: ["AgentLayout", "Agent"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/siteline/swiftui-introspect", from: "1.0.0"),
        .package(url: "https://github.com/markiv/SwiftUI-Shimmer", from: "1.0.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/JohnSundell/Splash", exact: "0.16.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "AgentLayout",
            dependencies: [
                "Agent",
                .product(name: "SwiftUIIntrospect", package: "swiftui-introspect"),
                .product(name: "Shimmer", package: "SwiftUI-Shimmer"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Splash", package: "Splash"),
            ]
        ),
        .target(
            name: "Agent"
        ),
        .testTarget(
            name: "AgentLayoutTests",
            dependencies: ["AgentLayout"]
        ),
        .testTarget(
            name: "AgentTests",
            dependencies: ["Agent"]
        ),
    ]
)
