import AppKit

// SwiftPM 可执行入口：以 accessory 模式启动一个无 Dock 图标的状态栏应用。
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// 打包脚本用：生成应用图标与状态栏图标预览后直接退出。
if let index = CommandLine.arguments.firstIndex(of: "--render-icons"),
   index + 1 < CommandLine.arguments.count {
    exit(IconExport.run(directory: CommandLine.arguments[index + 1]))
}

let appDelegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = appDelegate
app.run()
