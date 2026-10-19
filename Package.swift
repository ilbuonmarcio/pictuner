// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pictuner",
    platforms: [.macOS("26.6.2")],
    products: [.executable(name: "Pictuner", targets: ["Pictuner"])],
    targets: [
        .executableTarget(name: "Pictuner"),
        .testTarget(name: "PictunerTests", dependencies: ["Pictuner"])
    ],
    swiftLanguageModes: [.v5]
)
