// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SugarLogger",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SugarLogger", targets: ["SugarLogger"])
    ],
    targets: [
        .target(
            name: "SugarLogger",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
