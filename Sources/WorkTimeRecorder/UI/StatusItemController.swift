import AppKit
import Combine

/// 状态栏图标控制器：负责图标绘制、实时文字与弹出面板。
@MainActor
final class StatusItemController: NSObject {
    private let store: AppStore
    private weak var actions: AppActions?
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let popoverController: PopoverViewController
    private var cancellable: AnyCancellable?

    init(store: AppStore, actions: AppActions) {
        self.store = store
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popoverController = PopoverViewController(store: store, actions: actions)
        super.init()

        popover.contentViewController = popoverController
        popover.behavior = .transient
        popover.animates = true

        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.font = Fonts.mono(11, .medium)
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
        }

        refresh()
        cancellable = store.observe { [weak self] in
            self?.refresh()
        }
    }

    func refresh() {
        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.make(
            progress: store.todayProgress,
            isWorking: store.isWorking,
            hasRecord: store.hasTodayRecords || store.isWorking
        )
        let text = store.menuBarText
        button.title = text.isEmpty ? "" : " " + text
        button.toolTip = "工时记录器 · \(store.statusTitle) · \(store.statusSubtitle)"
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popoverController.refresh()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// 演示/截图模式：主动展开面板。
    func showPopoverForDemo() {
        if !popover.isShown {
            togglePopover(nil)
        }
    }
}
