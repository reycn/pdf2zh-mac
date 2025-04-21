// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PDFMathTranslate",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "PDFMathTranslate", targets: ["PDFMathTranslate"])
    ],
    dependencies: [
        // Dependencies would go here
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "PDFMathTranslate",
            dependencies: [],
            path: "Sources"
        )
    ]
)
