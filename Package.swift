// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Trova",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TrovaCore", targets: ["TrovaCore"]),
        .executable(name: "trova", targets: ["trova"]),
    ],
    dependencies: [
        // SQLite + FTS5 tam metin arama için olgun bir Swift sarmalayıcı.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // CLI argüman ayrıştırma.
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "TrovaCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .executableTarget(
            name: "trova",
            dependencies: [
                "TrovaCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "TrovaCoreTests",
            dependencies: ["TrovaCore"]
        ),
    ]
)
