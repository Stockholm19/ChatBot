// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "kudos-vapor",
    platforms: [
        .macOS(.v13) // Указываем, что проект для macOS 13 или новее
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.90.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.10.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.2.0")
    ],
    targets: [
        .executableTarget(
            name: "Run",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
            ],
            path: "Sources/Run"
        )
    ]
)
