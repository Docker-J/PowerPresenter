// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PowerPresenter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PowerPresenter", targets: ["PowerPresenter"])
    ],
    targets: [
        .executableTarget(
            name: "PowerPresenter",
            path: "Sources/PowerPresenter"
        )
    ]
)
