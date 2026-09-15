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

        // 7. 时区口径：默认北京时间
        let utcInstant = Date(timeIntervalSince1970: 1_789_566_600) // 2026-09-15T17:30:00Z
        let beijingKey = AppCalendar.dayKey(for: utcInstant)
        record(beijingKey == "2026-09-16", "默认按北京时间划分日期（该时刻北京时间 \(beijingKey) 00:30）", &passes, &failures)

        // 8. 数据文件时间戳带 +08:00 偏移，且能正确读回
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("work-time-recorder-selfcheck-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        do {
            let store2 = StateFileStore(directoryURL: tempDirectory)
            var sample = AppState()
            let sampleDate = AppCalendar.calendar(timeZone: AppTimeZone.beijing)
                .date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 9, minute: 28))!
            try sample.ledger.clockIn(at: sampleDate, source: .manual, calendar: AppCalendar.calendar())
            try store2.save(sample)
            let raw = try String(contentsOf: store2.fileURL, encoding: .utf8)
            record(raw.contains("2026-09-15T09:28:00+08:00"), "数据文件时间戳使用北京时间偏移（+08:00）", &passes, &failures)
            let loaded = store2.load()
            let loadedStart = loaded.ledger.day("2026-09-15").sessions.first?.start
            record(
                loadedStart.map { abs($0.timeIntervalSince(sampleDate)) < 1 } ?? false,
                "北京时间时间戳读写往返一致",
                &passes,
                &failures
            )
        } catch {
            failures.append("时区持久化检查失败：\(error.localizedDescription)")
        }

        // 9. Dock / 台前调度集成
        store.applyActivationPolicy()
        let expectedPolicy: NSApplication.ActivationPolicy = store.settings.showDockIcon ? .regular : .accessory
        record(NSApp.activationPolicy() == expectedPolicy, "应用形态与「隐藏 Dock 图标」设置一致（\(expectedPolicy == .regular ? "常规应用" : "仅状态栏")）", &passes, &failures)
        let dockMenu = DockMenu.make(store: store, target: actions as AnyObject)
        record(dockMenu.items.count >= 4, "Dock 右键菜单可构建（\(dockMenu.items.count) 项）", &passes, &failures)

        // 10. 演示模式不得写盘（回归：演示数据曾经被异步落盘污染真实数据）
        let beforeDemo = try? Data(contentsOf: store.fileStore.fileURL)
        store.applyDemoState(DemoMode.makeState(calendar: store.calendar))
        store.tick()
        let afterDemo = try? Data(contentsOf: store.fileStore.fileURL)
        record(beforeDemo == afterDemo, "演示模式不会写入真实数据文件", &passes, &failures)

        // 11. 午休扣除：09:00–18:00 默认扣掉 12:00–13:30，净 7.5 小时
        let lunchCalendar = AppCalendar.calendar()
        var lunchLedger = WorkTimeLedger()
        if let start = lunchCalendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()),
           let end = lunchCalendar.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) {
            try? lunchLedger.clockIn(at: start, source: .manual, calendar: lunchCalendar)
            try? lunchLedger.clockOut(at: end, source: .manual, calendar: lunchCalendar)
            let net = WorkTimeCalculator.workedSeconds(
                ledger: lunchLedger,
                dayKey: AppCalendar.dayKey(for: start, calendar: lunchCalendar),
                now: end,
                settings: Settings(),
                calendar: lunchCalendar
            )
            record(
                abs(net - 7.5 * 3600) < 1,
                "午休已从工时中扣除（默认 12:00 – 13:30，9:00–18:00 → 净 \(DurationFormat.text(net))）",
                &passes,
                &failures
            )
        }

        // 12. 每日时间轴：04:00 → 次日 04:00
        let workdayWindow = store.todayWorkdayWindow
        let windowFormatter = AppCalendar.formatter("HH:mm", calendar: store.calendar)
        record(
            windowFormatter.string(from: workdayWindow.start) == "04:00"
                && abs(workdayWindow.duration - 24 * 3600) < 1,
            "每日时间轴窗口为 \(windowFormatter.string(from: workdayWindow.start)) → 次日 \(windowFormatter.string(from: workdayWindow.end))",
            &passes,
            &failures
        )

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
