// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "konjac",
    platforms: [.macOS(.v14)],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b12119/llama-b12119-xcframework.zip",
            checksum: "9a170d568a0470cefddb5ddad2a5093ccbd13042077ca301cd399b11ef83e742"
        ),
        .executableTarget(
            name: "Konjac",
            dependencies: ["llama"]
        ),
        .testTarget(
            name: "KonjacTests",
            dependencies: ["Konjac"]
        ),
    ]
)
