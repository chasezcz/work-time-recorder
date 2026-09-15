import AppKit

/// Dock 右键菜单：快速打卡 + 打开窗口。
@MainActor
enum DockMenu {
    static func make(store: AppStore, target: AnyObject) -> NSMenu {
        let menu = NSMenu()

        let status = NSMenuItem(
            title: "\(store.statusTitle) · \(store.statusSubtitle)",
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())

        if store.isWorking {
            add(menu, title: "下班打卡", symbol: "moon.stars.fill", selector: #selector(AppDelegate.dockClockOut), target: target)
        } else {
            add(menu, title: "上班打卡", symbol: "sun.max.fill", selector: #selector(AppDelegate.dockClockIn), target: target)
            if store.canUndoClockOut {
                add(menu, title: "撤销下班（回来加班）", symbol: "arrow.uturn.backward", selector: #selector(AppDelegate.dockUndoClockOut), target: target)
            }
        }

        menu.addItem(.separator())
        add(menu, title: "打开工时分析", symbol: "chart.bar.xaxis", selector: #selector(AppDelegate.showAnalysis), target: target)
        add(menu, title: "设置…", symbol: "gearshape", selector: #selector(AppDelegate.showSettings), target: target)
        return menu
    }

    private static func add(_ menu: NSMenu, title: String, symbol: String?, selector: Selector, target: AnyObject) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = target
        if let symbol {
            item.image = UI.symbolImage(symbol, size: 13, weight: .medium)
        }
        menu.addItem(item)
    }
}
