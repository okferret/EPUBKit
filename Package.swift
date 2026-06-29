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
    
    targets: [
        .binaryTarget(
            name: "EPUBKit",
            path: "output/EPUBKit.xcframework"
        )
    ]
)
