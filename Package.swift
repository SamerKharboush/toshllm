// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XeonLLM",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "XeonLLM", path: "Sources"),
        .testTarget(name: "XeonLLMTests", dependencies: ["XeonLLM"], path: "Tests"),
    ]
)
