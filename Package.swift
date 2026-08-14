// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SiliconNotepadPlusPlus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "KevitPlusPlus",
            targets: ["SiliconNotepadPlusPlus"]
        ),
        .executable(
            name: "LogicTests",
            targets: ["LogicTests"]
        ),
        .library(
            name: "SiliconNotepadCore",
            targets: ["SiliconNotepadCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/krzyzanowskim/STTextView", from: "2.2.2"),
        .package(url: "https://github.com/krzyzanowskim/STTextView-Plugin-Neon", revision: "0.8.1")
    ],
    targets: [
        .target(
            name: "SiliconNotepadCore",
            dependencies: [
                .product(name: "STTextView", package: "STTextView"),
                .product(name: "STTextView-Plugin-Neon", package: "STTextView-Plugin-Neon")
            ],
            path: "Sources/SiliconNotepadCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("JavaScriptCore"),
                .linkedFramework("WebKit")
            ]
        ),
        .executableTarget(
            name: "SiliconNotepadPlusPlus",
            dependencies: ["SiliconNotepadCore"],
            path: "Sources/SiliconNotepadPlusPlus"
        ),
        .executableTarget(
            name: "LogicTests",
            dependencies: ["SiliconNotepadCore"],
            path: "Sources/LogicTests"
        )
    ]
)
