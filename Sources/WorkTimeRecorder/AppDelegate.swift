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

        buildMainMenu()
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

    /// 点击 Dock 图标时的标准行为：没有可见窗口就打开工时分析。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showAnalysis()
        }
        return true
    }

    /// Dock 右键菜单：快速上下班打卡。
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        DockMenu.make(store: store, target: self)
    }

    @objc func showAnalysis() {
        NSApp.activate(ignoringOtherApps: true)
        if analysisWindowController == nil {
            analysisWindowController = AnalysisWindowController(store: store)
        }
        analysisWindowController?.showWindow(nil)
    }

    @objc func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(store: store)
        }
        settingsWindowController?.showWindow(nil)
    }

    // MARK: - Dock 快捷动作

    @objc func dockClockIn() {
        store.clockIn()
    }

    @objc func dockClockOut() {
        store.clockOut()
    }

    @objc func dockUndoClockOut() {
        store.undoLastClockOut()
    }

    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    // MARK: - 主菜单（常规应用需要）

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "关于工时记录器", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏工时记录器", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出工时记录器", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}

extension AppDelegate: NSMenuItemValidation {
    /// Dock 菜单项根据当前状态启用/禁用由构建时决定，这里做兜底校验。
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(dockClockOut), #selector(dockUndoClockOut):
            return true
        default:
            return true
        }
    }
}
