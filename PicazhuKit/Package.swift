// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PicazhuKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PicazhuCore", targets: ["PicazhuCore"]),
        .library(name: "PicazhuData", targets: ["PicazhuData"]),
        .library(name: "PicazhuMedia", targets: ["PicazhuMedia"]),
        .library(name: "PicazhuVision", targets: ["PicazhuVision"]),
        .library(name: "PicazhuIndexing", targets: ["PicazhuIndexing"]),
        .library(name: "PicazhuPreview", targets: ["PicazhuPreview"]),
        .library(name: "PicazhuSearch", targets: ["PicazhuSearch"]),
        .library(name: "PicazhuAI", targets: ["PicazhuAI"]),
        .library(name: "PicazhuDiagnostics", targets: ["PicazhuDiagnostics"]),
        .library(name: "PicazhuUI", targets: ["PicazhuUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "PicazhuCore"),
        .target(
            name: "PicazhuData",
            dependencies: [
                "PicazhuCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "PicazhuMedia",
            dependencies: ["PicazhuCore"]
        ),
        .target(
            name: "PicazhuVision",
            dependencies: ["PicazhuCore"]
        ),
        .target(
            name: "PicazhuIndexing",
            dependencies: ["PicazhuCore", "PicazhuData", "PicazhuMedia"]
        ),
        .target(
            name: "PicazhuPreview",
            dependencies: ["PicazhuCore", "PicazhuMedia"]
        ),
        .target(
            name: "PicazhuSearch",
            dependencies: [
                "PicazhuCore",
                "PicazhuData",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "PicazhuAI",
            dependencies: ["PicazhuCore", "PicazhuData"]
        ),
        .target(
            name: "PicazhuDiagnostics",
            dependencies: ["PicazhuCore", "PicazhuData", "PicazhuIndexing", "PicazhuMedia"]
        ),
        .target(
            name: "PicazhuUI",
            dependencies: ["PicazhuCore"]
        ),
        .testTarget(
            name: "PicazhuDataTests",
            dependencies: ["PicazhuData"]
        ),
        .testTarget(
            name: "PicazhuIndexingTests",
            dependencies: ["PicazhuIndexing"]
        ),
        .testTarget(
            name: "PicazhuMediaTests",
            dependencies: ["PicazhuMedia"]
        ),
        .testTarget(
            name: "PicazhuSearchTests",
            dependencies: ["PicazhuSearch"]
        ),
        .testTarget(
            name: "PicazhuAITests",
            dependencies: ["PicazhuAI", "PicazhuData"]
        ),
        .testTarget(
            name: "PicazhuVisionTests",
            dependencies: ["PicazhuVision"]
        ),
    ]
)
