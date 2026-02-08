// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Bonsplit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Bonsplit", targets: ["Bonsplit"]),
    ],
    targets: [
        .target(name: "Bonsplit", dependencies: [], path: "Sources/Bonsplit"),
    ]
)
