import AppKit

/// 打开主窗口/设置窗口的统一入口，供状态栏面板调用。
@MainActor
protocol AppActions: AnyObject {
    func showAnalysis()
    func showSettings()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, AppActions {
    private var statusItemController: StatusItemController?
    private var analysisWindowController: AnalysisWindowController?
    private var settingsWindowController: SettingsWindowController?

    private var store: AppStore { .shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-check") {
            let code = SelfCheck.run(store: store, actions: self)
            exit(code)
        }

        store.start()
        statusItemController = StatusItemController(store: store, actions: self)

        if CommandLine.arguments.contains("--demo") {
            DemoMode.apply(to: store)
            showAnalysis()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.statusItemController?.showPopoverForDemo()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func showAnalysis() {
        NSApp.activate(ignoringOtherApps: true)
        if analysisWindowController == nil {
            analysisWindowController = AnalysisWindowController(store: store)
        }
        analysisWindowController?.showWindow(nil)
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(store: store)
        }
        settingsWindowController?.showWindow(nil)
    }
}
