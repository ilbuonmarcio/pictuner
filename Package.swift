// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PicTuner",
    platforms: [.macOS("26.6.2")],
    products: [.executable(name: "PicTuner", targets: ["Pictuner"])],
    targets: [
        .executableTarget(name: "Pictuner"),
        .testTarget(name: "PictunerTests", dependencies: ["Pictuner"])
    ],
    swiftLanguageModes: [.v5]
)
