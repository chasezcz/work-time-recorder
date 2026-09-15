// swift-tools-version: 5.9
import Foundation
import PackageDescription

/// 只安装了 Command Line Tools 时，Swift Testing 的宏插件位于这个子目录，
/// SwiftPM 在增量构建时可能不会自动带上该搜索路径，这里显式补上。
/// 装有完整 Xcode 的环境不受影响。
let commandLineToolsTestingPluginPath = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSwiftSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: commandLineToolsTestingPluginPath)
    ? [.unsafeFlags(["-plugin-path", commandLineToolsTestingPluginPath])]
    : []

let package = Package(
    name: "WorkTimeRecorder",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WorkTimeRecorder", targets: ["WorkTimeRecorder"]),
        .library(name: "WorkTimeCore", targets: ["WorkTimeCore"])
    ],
    targets: [
        .target(name: "WorkTimeCore"),
        .executableTarget(name: "WorkTimeRecorder", dependencies: ["WorkTimeCore"]),
        .testTarget(
            name: "WorkTimeCoreTests",
            dependencies: ["WorkTimeCore"],
            swiftSettings: testSwiftSettings
        )
    ]
)
