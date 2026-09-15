import AppKit
import WorkTimeCore

/// `--self-check`：不弹窗地构建全部界面并验证布局，用于打包前的自动检查。
@MainActor
enum SelfCheck {
    static func run(store: AppStore, actions: AppActions) -> Int32 {
        var failures: [String] = []
        var passes: [String] = []

        // 1. 状态栏面板
        let popover = PopoverViewController(store: store, actions: actions)
        let popoverView = popover.view
        popoverView.frame = NSRect(x: 0, y: 0, width: 344, height: 600)
        popoverView.layoutSubtreeIfNeeded()
        let popoverSize = popoverView.fittingSize
        record(
            popoverSize.width >= 320 && popoverSize.height >= 240,
            "状态栏面板布局 \(Int(popoverSize.width))×\(Int(popoverSize.height))",
            &passes,
            &failures
        )

        // 2. 分析窗口（统计 / 节假日 / 导出）
        let analysisController = AnalysisWindowController(store: store)
        if let window = analysisController.window {
            window.setFrame(NSRect(x: 0, y: 0, width: 980, height: 700), display: false)
            window.contentView?.layoutSubtreeIfNeeded()
            let size = window.contentView?.bounds.size ?? .zero
            let buttons = countViews(of: NSButton.self, in: window.contentView)
            let charts = countViews(of: BarChartView.self, in: window.contentView)
            let segments = countViews(of: NSSegmentedControl.self, in: window.contentView)
            record(
                size.width >= 900 && size.height >= 500 && buttons >= 3 && charts >= 1 && segments >= 1,
                "分析窗口布局 \(Int(size.width))×\(Int(size.height)) · 按钮 \(buttons) 个 · 图表 \(charts) 个",
                &passes,
                &failures
            )
        } else {
            failures.append("分析窗口未能创建")
        }

        // 3. 设置窗口
        let settingsController = SettingsWindowController(store: store)
        if let window = settingsController.window {
            window.setFrame(NSRect(x: 0, y: 0, width: 620, height: 720), display: false)
            window.contentView?.layoutSubtreeIfNeeded()
            let size = window.contentView?.bounds.size ?? .zero
            let switches = countViews(of: NSSwitch.self, in: window.contentView)
            record(
                size.width >= 560 && size.height >= 500 && switches >= 4,
                "设置窗口布局 \(Int(size.width))×\(Int(size.height)) · 开关 \(switches) 个",
                &passes,
                &failures
            )
        } else {
            failures.append("设置窗口未能创建")
        }

        // 4. 状态栏图标可绘制
        let icon = MenuBarIcon.make(progress: 0.6, isWorking: true, hasRecord: true)
        record(icon.size.width > 8 && icon.isTemplate, "状态栏图标绘制正常", &passes, &failures)

        // 5. 统计与导出链路
        let stats = store.periodStats(granularity: .week, offset: 0)
        record(stats.buckets.count == 7, "周统计分桶 \(stats.buckets.count) 个", &passes, &failures)
        let csv = store.summaryCSV(preset: .thisMonth)
        record(csv.hasPrefix("\u{FEFF}") && csv.contains("日期"), "汇总 CSV 生成正常", &passes, &failures)

        // 6. 账本核心逻辑（使用内存数据，不写入用户文件）
        var ledger = WorkTimeLedger()
        let calendar = store.calendar
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        do {
            try ledger.clockIn(at: start, source: .manual, calendar: calendar)
            try ledger.clockOut(at: start.addingTimeInterval(8.5 * 3600), source: .autoLock, calendar: calendar)
            try ledger.undoLastClockOut()
            record(ledger.isWorking, "打卡 / 下班 / 撤销链路正常", &passes, &failures)
        } catch {
            failures.append("账本逻辑异常：\(error.localizedDescription)")
        }

        for line in passes { print("  ✅ \(line)") }
        for line in failures { print("  ❌ \(line)") }
        print(failures.isEmpty ? "self-check 通过（\(passes.count) 项）" : "self-check 失败（\(failures.count) 项）")
        return failures.isEmpty ? 0 : 1
    }

    private static func record(
        _ condition: Bool,
        _ message: String,
        _ passes: inout [String],
        _ failures: inout [String]
    ) {
        if condition { passes.append(message) } else { failures.append(message) }
    }

    private static func countViews<T: NSView>(of type: T.Type, in view: NSView?) -> Int {
        guard let view else { return 0 }
        var total = view is T ? 1 : 0
        for subview in view.subviews {
            total += countViews(of: type, in: subview)
        }
        return total
    }

}
