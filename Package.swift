// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChatBot",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // исполняемый продукт (binary) и библиотека для переиспользования
        .executable(name: "Run", targets: ["Run"]),
        .library(name: "App", targets: ["App"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.92.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.5.0")
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver")
            ],
            path: "Sources/App"
        ),
        .executableTarget(
            name: "Run",
            dependencies: [
                .target(name: "App"),
                .product(name: "Vapor", package: "vapor") // для Application/Environment
            ],
            path: "Sources/Run"
        )
    ]
)
