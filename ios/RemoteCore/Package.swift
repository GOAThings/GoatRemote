// swift-tools-version:5.9
import PackageDescription

// O protocolo do comando das Android TV, sem nada da Apple: testa-se em Linux.
let package = Package(
    name: "RemoteCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "RemoteCore", targets: ["RemoteCore"])],
    targets: [
        .target(name: "RemoteCore"),
        .testTarget(name: "RemoteCoreTests", dependencies: ["RemoteCore"]),
    ]
)
