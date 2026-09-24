// swift-tools-version:5.9
//
// VENDORING NOTES
//
// Upstream: https://github.com/migueldeicaza/SwiftTerm
// Version:  v1.20.0 (commit 5d14406844143538cd8f8851d2d8a67c1fe443e5)
// License:  MIT (see LICENSE)
//
// Kept: Sources/SwiftTerm (the shared, Apple, and Mac sources) and LICENSE.
// Dropped: the iOS sources, DocC catalog, tests, fuzz/termcast/benchmark targets,
//   and the swift-argument-parser and swift-docc-plugin dependencies.
// Replaced: the SwiftTermBuildInfoPlugin build tool, which ran git at build time,
//   by the static Sources/SwiftTerm/SwiftTermBuildInfo.swift.
// Omitted resource: Apple/Metal/Shaders.metal. Metal rendering is opt-in
//   (`setUseMetal`); without a metallib the renderer reports an error and the view
//   keeps its CoreGraphics renderer, which is the default.
// Upstream Swift sources are otherwise unmodified.
//
// Upgrading: copy Sources/SwiftTerm from the new tag with the same exclusions,
// regenerate SwiftTermBuildInfo.swift for that tag, and update third_party/NOTICE.

import PackageDescription

let package = Package(
    name: "SwiftTerm",
    platforms: [.macOS(.v11)],
    products: [.library(name: "SwiftTerm", targets: ["SwiftTerm"])],
    targets: [.target(name: "SwiftTerm", path: "Sources/SwiftTerm")]
)
