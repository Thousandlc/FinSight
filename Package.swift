// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Youshu",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "YoushuFoundation", targets: ["YoushuFoundation"]),
        .library(name: "YoushuLogging", targets: ["YoushuLogging"]),
        .library(name: "YoushuDomain", targets: ["YoushuDomain"]),
        .library(name: "YoushuData", targets: ["YoushuData"]),
        .library(name: "YoushuAI", targets: ["YoushuAI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.8.0"),
    ],
    targets: [
        .target(
            name: "YoushuFoundation",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ],
            path: "Infrastructure/YoushuFoundation/Sources/YoushuFoundation"
        ),
        .target(
            name: "YoushuLogging",
            dependencies: ["YoushuFoundation"],
            path: "Infrastructure/YoushuLogging/Sources/YoushuLogging"
        ),
        .target(
            name: "YoushuDomain",
            dependencies: ["YoushuFoundation"],
            path: "Modules/YoushuDomain/Sources/YoushuDomain"
        ),
        .target(
            name: "YoushuData",
            dependencies: ["YoushuDomain", "YoushuLogging", "YoushuFoundation"],
            path: "Modules/YoushuData/Sources/YoushuData"
        ),
        .target(
            name: "YoushuAI",
            dependencies: ["YoushuDomain", "YoushuFoundation"],
            path: "Modules/YoushuAI/Sources/YoushuAI"
        ),
        .testTarget(
            name: "YoushuFoundationTests",
            dependencies: ["YoushuFoundation"],
            path: "Infrastructure/YoushuFoundation/Tests/YoushuFoundationTests"
        ),
        .testTarget(
            name: "YoushuDomainTests",
            dependencies: ["YoushuDomain", "YoushuData", "YoushuAI", "YoushuLogging"],
            path: "Modules/YoushuDomain/Tests/YoushuDomainTests"
        ),
        .testTarget(
            name: "YoushuDataTests",
            dependencies: ["YoushuData", "YoushuDomain", "YoushuFoundation"],
            path: "Modules/YoushuData/Tests/YoushuDataTests"
        ),
        .testTarget(
            name: "YoushuAITests",
            dependencies: ["YoushuAI", "YoushuDomain", "YoushuData"],
            path: "Modules/YoushuAI/Tests/YoushuAITests"
        ),
    ]
)
