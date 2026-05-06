// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipStack",
    // MenuBarExtra 需要 macOS 13+；Monterey(12) 若要支持需改用 NSStatusItem 等实现。
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClipStack", targets: ["ClipStack"])
    ],
    targets: [
        .target(
            name: "CHotkey",
            path: "Sources/CHotkey",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Carbon", .when(platforms: [.macOS]))
            ]
        ),
        .executableTarget(
            name: "ClipStack",
            dependencies: ["CHotkey"],
            path: "Sources/ClipStack",
            linkerSettings: [
                .linkedFramework("AVFoundation", .when(platforms: [.macOS]))
            ]
        )
    ]
)
