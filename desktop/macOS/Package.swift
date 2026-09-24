// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GrokDesktop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "GrokDesktop", targets: ["GrokDesktop"])],
    // The embedded terminal's emulator, vendored in-tree (see third_party/README.md).
    dependencies: [.package(path: "../../third_party/SwiftTerm")],
    targets: [
        .executableTarget(name: "GrokDesktop", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]),
        .testTarget(name: "GrokDesktopTests", dependencies: ["GrokDesktop"])
    ]
)
