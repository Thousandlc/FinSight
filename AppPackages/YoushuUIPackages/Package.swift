// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YoushuUIPackages",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "YoushuDesignSystem", targets: ["YoushuDesignSystem"]),
        .library(name: "YoushuUI", targets: ["YoushuUI"]),
        .library(name: "YoushuUIPreviewMocks", targets: ["YoushuUIPreviewMocks"]),
    ],
    dependencies: [
        .package(name: "Youshu", path: "../.."),
    ],
    targets: [
        .target(
            name: "YoushuDesignSystem",
            dependencies: [
                .product(name: "YoushuFoundation", package: "Youshu"),
            ],
            path: "../../Modules/YoushuDesignSystem/Sources/YoushuDesignSystem",
            resources: [.process("Resources")]
        ),
        .target(
            name: "YoushuUI",
            dependencies: [
                "YoushuDesignSystem",
                .product(name: "YoushuDomain", package: "Youshu"),
                .product(name: "YoushuData", package: "Youshu"),
                .product(name: "YoushuAI", package: "Youshu"),
            ],
            path: "../../Modules/YoushuUI/Sources/YoushuUI"
        ),
        .target(
            name: "YoushuUIPreviewMocks",
            dependencies: [
                "YoushuUI",
                "YoushuDesignSystem",
                .product(name: "YoushuDomain", package: "Youshu"),
                .product(name: "YoushuFoundation", package: "Youshu"),
                .product(name: "YoushuAI", package: "Youshu"),
            ],
            path: "../../Modules/YoushuUIPreviewMocks/Sources/YoushuUIPreviewMocks"
        ),
    ]
)
