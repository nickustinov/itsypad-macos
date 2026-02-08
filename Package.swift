// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "itsypad",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/CodeEditApp/CodeEditLanguages", from: "0.1.20"),
        .package(path: "Packages/Bonsplit"),
    ],
    targets: [
        .target(
            name: "ItsypadCore",
            dependencies: [
                .product(name: "CodeEditLanguages", package: "CodeEditLanguages"),
                .product(name: "Bonsplit", package: "Bonsplit"),
            ],
            path: "Sources",
            exclude: ["Info.plist", "itsypad.entitlements"],
            resources: [.process("Resources")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Sources/Info.plist"])
            ]
        ),
        .executableTarget(
            name: "itsypad",
            dependencies: ["ItsypadCore"],
            path: "Executable"
        ),
        .testTarget(
            name: "ItsypadTests",
            dependencies: ["ItsypadCore"],
            path: "Tests"
        ),
    ]
)
