// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GrokDesktop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "GrokDesktop", targets: ["GrokDesktop"])],
    targets: [
        .executableTarget(name: "GrokDesktop"),
        .testTarget(name: "GrokDesktopTests", dependencies: ["GrokDesktop"])
    ]
)
