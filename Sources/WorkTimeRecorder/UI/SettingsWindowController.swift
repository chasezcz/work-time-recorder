import AppKit
import Combine
import WorkTimeCore

/// 设置窗口。
@MainActor
final class SettingsWindowController: NSWindowController {
    init(store: AppStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "工时记录器设置"
        window.minSize = NSSize(width: 560, height: 480)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentViewController = SettingsViewController(store: store)
        window.setContentSize(NSSize(width: 620, height: 720))
        window.center()
        window.setFrameAutosaveName("WorkTimeSettingsWindow")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

@MainActor
final class SettingsViewController: NSViewController {
    private let store: AppStore
    private var cancellable: AnyCancellable?

    private let targetValueLabel = UI.label("", font: Fonts.mono(13, .semibold))
    private lazy var targetStepper: NSStepper = {
        let stepper = NSStepper()
        stepper.minValue = 1
        stepper.maxValue = 16
        stepper.increment = 0.5
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = #selector(targetStepperChanged(_:))
        stepper.translatesAutoresizingMaskIntoConstraints = false
        return stepper
    }()

    private lazy var quickTargetButtons: NSStackView = {
        let stack = UI.horizontalStack(spacing: 6)
        for hours in [6.0, 7.0, 7.5, 8.0, 9.0, 10.0] {
            let button = NSButton(title: Self.hoursTitle(hours), target: self, action: #selector(quickTargetTapped(_:)))
            button.tag = Int(hours * 2)
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(UI.flexibleSpace())
        return stack
    }()

    private lazy var autoClockInSwitch: NSSwitch = makeSwitch(action: #selector(autoClockInToggled(_:)))
    private lazy var autoClockInPicker: NSDatePicker = {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textField
        picker.datePickerElements = .hourMinute
        picker.target = self
        picker.action = #selector(autoClockInTimeChanged(_:))
        picker.translatesAutoresizingMaskIntoConstraints = false
        return picker
    }()

    private lazy var autoClockOutSwitch: NSSwitch = makeSwitch(action: #selector(autoClockOutToggled(_:)))
    private lazy var notifySwitch: NSSwitch = makeSwitch(action: #selector(notifyToggled(_:)))
    private let notificationStatusLabel = UI.label("读取中…", font: Fonts.system(11), color: .secondaryLabelColor)

    private lazy var countryField: NSTextField = {
        let field = NSTextField(string: "CN")
        field.alignment = .center
        field.target = self
        field.action = #selector(countryChanged(_:))
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 64).isActive = true
        return field
    }()
    private let holidayCacheLabel = UI.label("", font: Fonts.system(11), color: .secondaryLabelColor)
    private lazy var refreshHolidayButton = NSButton(title: "立即更新", target: self, action: #selector(refreshHolidays))

    private lazy var menuBarTimeSwitch: NSSwitch = makeSwitch(action: #selector(menuBarTimeToggled(_:)))
    private lazy var hideDockIconSwitch: NSSwitch = makeSwitch(action: #selector(hideDockIconToggled(_:)))
    private lazy var timeZonePopup: NSPopUpButton = {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.target = self
        popup.action = #selector(timeZoneChanged(_:))
        return popup
    }()
    private let dataPathLabel = UI.label("", font: Fonts.system(11), color: .secondaryLabelColor)

    init(store: AppStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        let content = UI.verticalStack(spacing: 18)
        content.alignment = .width
        let scrollView = ScrollContainer.make(
            content: content,
            horizontalPadding: 24,
            topPadding: 20,
            bottomPadding: 24
        )
        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        content.addArrangedSubview(makeTargetSection())
        content.addArrangedSubview(makeAutoClockInSection())
        content.addArrangedSubview(makeAutoClockOutSection())
        content.addArrangedSubview(makeNotificationSection())
        content.addArrangedSubview(makeHolidaySection())
        content.addArrangedSubview(makeMenuBarSection())
        content.addArrangedSubview(makeIntegrationSection())
        content.addArrangedSubview(makeTimeZoneSection())
        content.addArrangedSubview(makeDataSection())
        content.addArrangedSubview(makeAboutSection())

        view = root
        refresh()
        Task { [weak self] in
            guard let self else { return }
            self.notificationStatusLabel.stringValue = await NotificationService.shared.authorizationStatusDescription()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        cancellable = store.observe { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - 分区

    private func makeTargetSection() -> NSView {
        section(
            title: "工时目标",
            rows: [
                row(
                    title: "每日目标工时",
                    control: {
                        let stack = UI.horizontalStack(spacing: 8, alignment: .centerY)
                        stack.addArrangedSubview(self.targetValueLabel)
                        stack.addArrangedSubview(self.targetStepper)
                        return stack
                    }()
                ),
                quickTargetButtons
            ],
            hint: "也可以在状态栏面板里为“今天”单独设置目标，不影响其他日期。"
        )
    }

    private func makeAutoClockInSection() -> NSView {
        section(
            title: "自动上班",
            rows: [
                row(title: "解锁电脑后自动开始上班", control: autoClockInSwitch),
                row(title: "时间门槛", control: autoClockInPicker)
            ],
            hint: "当天在时间门槛之后第一次解锁（含从休眠唤醒）时，自动记录上班时间。如果当天已经有打卡记录，则不会重复自动打卡。"
        )
    }

    private func makeAutoClockOutSection() -> NSView {
        section(
            title: "自动下班",
            rows: [row(title: "工时达标后，锁屏自动记录下班", control: autoClockOutSwitch)],
            hint: "只有“已达标 + 锁屏或休眠”同时满足时才自动打卡。回来后如果想继续加班，在状态栏面板点“撤销下班”即可恢复上班状态。"
        )
    }

    private func makeNotificationSection() -> NSView {
        let statusRow = UI.horizontalStack(spacing: 8, alignment: .centerY)
        statusRow.addArrangedSubview(notificationStatusLabel)
        statusRow.addArrangedSubview(UI.flexibleSpace())
        let openButton = NSButton(title: "打开系统通知设置", target: self, action: #selector(openNotificationSettings))
        openButton.bezelStyle = .rounded
        openButton.controlSize = .small
        statusRow.addArrangedSubview(openButton)

        return section(
            title: "提醒",
            rows: [
                row(title: "工时达标时发送系统通知", control: notifySwitch),
                statusRow
            ],
            hint: "通知会出现在屏幕右上角。若显示“未打包运行”，请使用 scripts/build_app.sh 打包成 .app 后再运行。"
        )
    }

    private func makeHolidaySection() -> NSView {
        let countryRow = UI.horizontalStack(spacing: 8, alignment: .centerY)
        countryRow.addArrangedSubview(UI.label("国家/地区代码", font: Fonts.system(13)))
        countryRow.addArrangedSubview(UI.flexibleSpace())
        countryRow.addArrangedSubview(countryField)

        let cacheRow = UI.horizontalStack(spacing: 8, alignment: .centerY)
        cacheRow.addArrangedSubview(UI.label("本地缓存", font: Fonts.system(13)))
        cacheRow.addArrangedSubview(UI.flexibleSpace())
        cacheRow.addArrangedSubview(holidayCacheLabel)
        refreshHolidayButton.bezelStyle = .rounded
        refreshHolidayButton.controlSize = .small
        cacheRow.addArrangedSubview(refreshHolidayButton)

        return section(
            title: "节假日",
            rows: [countryRow, cacheRow],
            hint: "每次启动都会尝试从公开 API 更新并写入本地缓存；CN 使用 holiday-cn（含放假区间与调休补班日），失败时回退 Nager.Date，离线时继续使用缓存。"
        )
    }

    private func makeMenuBarSection() -> NSView {
        section(
            title: "状态栏",
            rows: [row(title: "在状态栏显示实时工时", control: menuBarTimeSwitch)],
            hint: "状态栏图标本身就是今日进度环：外圈表示目标完成度，实心圆点表示正在上班，达标后变成对勾。"
        )
    }

    private func makeIntegrationSection() -> NSView {
        section(
            title: "Dock 与台前调度",
            rows: [
                row(title: "隐藏 Dock 图标（只保留状态栏）", control: hideDockIconSwitch)
            ],
            hint: "不隐藏时，应用会出现在 Dock 与台前调度里；点击 Dock 图标可打开工时分析，右键 Dock 图标可以快速打卡。勾选隐藏后，应用只保留右上角状态栏图标。"
        )
    }

    private func makeTimeZoneSection() -> NSView {
        section(
            title: "时区",
            rows: [row(title: "统计与记录时区", control: timeZonePopup)],
            hint: "决定一天的划分、界面时间显示，以及数据文件中时间戳的偏移量。默认北京时间（UTC+8），历史记录的时间点不会被改写。"
        )
    }

    private func makeDataSection() -> NSView {
        let pathRow = UI.horizontalStack(spacing: 8, alignment: .centerY)
        pathRow.addArrangedSubview(UI.label("数据文件", font: Fonts.system(13)))
        pathRow.addArrangedSubview(UI.flexibleSpace())
        pathRow.addArrangedSubview(dataPathLabel)
        let revealButton = NSButton(title: "显示", target: self, action: #selector(revealDataFile))
        revealButton.bezelStyle = .rounded
        revealButton.controlSize = .small
        pathRow.addArrangedSubview(revealButton)

        let clearRow = UI.horizontalStack(spacing: 8, alignment: .centerY)
        clearRow.addArrangedSubview(UI.label("清空打卡数据", font: Fonts.system(13)))
        clearRow.addArrangedSubview(UI.flexibleSpace())
        let clearButton = NSButton(title: "清空…", target: self, action: #selector(clearData))
        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .small
        clearButton.contentTintColor = Theme.danger
        clearRow.addArrangedSubview(clearButton)

        return section(
            title: "数据",
            rows: [pathRow, clearRow],
            hint: "全部数据仅保存在本机，不会上传；只有节假日需要联网获取。时间戳按上面的时区写入（默认北京时间 UTC+8）。CSV 导出在“工时分析 → 导出”里。"
        )
    }

    private func makeAboutSection() -> NSView {
        let versionRow = UI.horizontalStack(spacing: 8, alignment: .centerY)
        versionRow.addArrangedSubview(UI.label("版本", font: Fonts.system(13)))
        versionRow.addArrangedSubview(UI.flexibleSpace())
        versionRow.addArrangedSubview(UI.label(Self.version, font: Fonts.mono(12), color: .secondaryLabelColor))
        return section(title: "关于", rows: [versionRow], hint: nil)
    }

    // MARK: - 组件工厂

    private func section(title: String, rows: [NSView], hint: String?) -> NSView {
        let stack = UI.verticalStack(spacing: 10)
        stack.alignment = .width
        stack.addArrangedSubview(makeSectionHeader(title))
        let card = CardView(padding: 14, spacing: 10)
        rows.forEach { card.contentStack.addArrangedSubview($0) }
        stack.addArrangedSubview(card)
        if let hint {
            stack.addArrangedSubview(UI.multilineLabel(hint, font: Fonts.system(10.5)))
        }
        return stack
    }

    private func row(title: String, control: NSView) -> NSView {
        let row = UI.horizontalStack(spacing: 12, alignment: .centerY)
        row.addArrangedSubview(UI.label(title, font: Fonts.system(13)))
        row.addArrangedSubview(UI.flexibleSpace())
        row.addArrangedSubview(control)
        return row
    }

    private func makeSwitch(action: Selector) -> NSSwitch {
        let toggle = NSSwitch()
        toggle.target = self
        toggle.action = action
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }

    // MARK: - 刷新

    private func refresh() {
        let settings = store.settings
        targetValueLabel.stringValue = DurationFormat.text(settings.dailyTargetSeconds)
        targetStepper.doubleValue = settings.dailyTargetSeconds / 3600

        autoClockInSwitch.state = settings.automaticClockInEnabled ? .on : .off
        autoClockInPicker.isEnabled = settings.automaticClockInEnabled
        autoClockInPicker.dateValue = autoClockInDate()
        autoClockOutSwitch.state = settings.automaticClockOutEnabled ? .on : .off
        notifySwitch.state = settings.notifyWhenTargetReached ? .on : .off

        if countryField.currentEditor() == nil {
            countryField.stringValue = settings.holidayCountryCode
        }

        let year = store.calendar.component(.year, from: Date())
        let current = store.holidays(year: year).count
        let next = store.holidays(year: year + 1).count
        if let updated = store.lastHolidayRefresh(year: year) {
            let stamp = AppCalendar.formatter("MM-dd HH:mm").string(from: updated)
            holidayCacheLabel.stringValue = "\(year) 年 \(current) 条 · \(year + 1) 年 \(next) 条 · 更新于 \(stamp)"
        } else {
            holidayCacheLabel.stringValue = "\(year) 年 \(current) 条 · \(year + 1) 年 \(next) 条"
        }

        if case .failed(let message) = store.holidayState {
            holidayCacheLabel.stringValue = message
        }

        menuBarTimeSwitch.state = settings.showTimeInMenuBar ? .on : .off
        hideDockIconSwitch.state = settings.showDockIcon ? .off : .on
        refreshTimeZonePopup(settings: settings)
        dataPathLabel.stringValue = store.dataFileURL.path
    }

    private func refreshTimeZonePopup(settings: Settings) {
        let menu = NSMenu()
        let beijing = NSMenuItem(title: AppTimeZone.displayName(identifier: AppTimeZone.beijingIdentifier), action: nil, keyEquivalent: "")
        beijing.representedObject = AppTimeZone.beijingIdentifier
        let system = NSMenuItem(title: AppTimeZone.displayName(identifier: AppTimeZone.systemIdentifier), action: nil, keyEquivalent: "")
        system.representedObject = AppTimeZone.systemIdentifier
        menu.addItem(beijing)
        menu.addItem(system)
        timeZonePopup.menu = menu

        let index = settings.timeZoneIdentifier == AppTimeZone.systemIdentifier ? 1 : 0
        timeZonePopup.selectItem(at: index)
    }

    private func autoClockInDate() -> Date {
        let settings = store.settings
        let base = store.calendar.startOfDay(for: Date())
        return store.calendar.date(
            bySettingHour: settings.autoClockInHour,
            minute: settings.autoClockInMinute,
            second: 0,
            of: base
        ) ?? base
    }

    // MARK: - 动作

    @objc private func targetStepperChanged(_ sender: NSStepper) {
        store.setDailyTarget(hours: sender.doubleValue)
    }

    @objc private func quickTargetTapped(_ sender: NSButton) {
        store.setDailyTarget(hours: Double(sender.tag) / 2)
    }

    @objc private func autoClockInToggled(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        store.updateSettings { $0.automaticClockInEnabled = enabled }
    }

    @objc private func autoClockInTimeChanged(_ sender: NSDatePicker) {
        let components = store.calendar.dateComponents([.hour, .minute], from: sender.dateValue)
        store.updateSettings { settings in
            settings.autoClockInHour = components.hour ?? 4
            settings.autoClockInMinute = components.minute ?? 0
        }
    }

    @objc private func autoClockOutToggled(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        store.updateSettings { $0.automaticClockOutEnabled = enabled }
    }

    @objc private func notifyToggled(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        store.updateSettings { $0.notifyWhenTargetReached = enabled }
    }

    @objc private func menuBarTimeToggled(_ sender: NSSwitch) {
        let enabled = sender.state == .on
        store.updateSettings { $0.showTimeInMenuBar = enabled }
    }

    @objc private func hideDockIconToggled(_ sender: NSSwitch) {
        let hidden = sender.state == .on
        store.updateSettings { $0.showDockIcon = !hidden }
    }

    @objc private func timeZoneChanged(_ sender: NSPopUpButton) {
        guard let identifier = sender.selectedItem?.representedObject as? String else { return }
        store.updateSettings { $0.timeZoneIdentifier = identifier }
    }

    @objc private func countryChanged(_ sender: NSTextField) {
        let code = sender.stringValue.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateSettings { $0.holidayCountryCode = code.isEmpty ? "CN" : code }
    }

    @objc private func refreshHolidays() {
        Task { await store.refreshHolidays() }
    }

    @objc private func openNotificationSettings() {
        NotificationService.shared.openSystemNotificationSettings()
    }

    @objc private func revealDataFile() {
        store.revealDataFileInFinder()
    }

    @objc private func clearData() {
        let alert = NSAlert()
        alert.messageText = "清空全部打卡数据？"
        alert.informativeText = "将删除本地保存的所有打卡记录，此操作不可恢复。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "清空")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        store.resetAllData()
    }

    private static func hoursTitle(_ hours: Double) -> String {
        hours.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(hours))h" : "\(hours)h"
    }

    private static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}
