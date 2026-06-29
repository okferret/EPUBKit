// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "EPUBKit",
    
    platforms: [
        .macOS(.v10_13),
        .iOS(.v12),
        .tvOS(.v12)
    ],
    
    products: [
        .library(name: "EPUBKit", targets: ["EPUBKit"]),
    ],
    
    dependencies: [
        .package(url: "https://github.com/tadija/AEXML.git", from: "4.0.0"),
        .package(url: "https://github.com/marmelroy/Zip.git", from: "2.0.0"),
    ],
    
    targets: [
        .target(
            name: "EPUBKit",
            dependencies: ["AEXML", "Zip"],
            path: "Sources/EPUBKit"
        ),
        .testTarget(
            name: "EPUBKitTests",
            dependencies: ["EPUBKit"],
            path: "Tests/EPUBKitTests",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
