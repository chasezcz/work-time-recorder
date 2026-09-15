import AppKit
import WorkTimeCore

/// 点击状态栏图标后弹出的快速面板。
@MainActor
final class PopoverViewController: NSViewController {
    private let store: AppStore
    private weak var actions: AppActions?

    // 头部
    private let dateLabel = UI.label("", font: Fonts.system(15, .semibold))
    private let offDayLabel = UI.label("休息日", font: Fonts.system(10, .medium), color: .secondaryLabelColor)
    private let holidayLabel = UI.label("", font: Fonts.system(10, .medium), color: Theme.warningText)
    private let demoBadge = StatusPillView()
    private let statusPill = StatusPillView()

    // 进度卡
    private let ringView = ProgressRingView()
    private let ringValueLabel = UI.label("--:--", font: Fonts.rounded(17, .semibold), alignment: .center)
    private let ringCaptionLabel = UI.label("尚未打卡", font: Fonts.system(10), color: .secondaryLabelColor, alignment: .center)
    private let targetRow = InfoRowView(title: "今日目标")
    private let secondRow = InfoRowView(title: "剩余")
    private let lunchRow = InfoRowView(title: "午休扣除")
    private let statusRow = InfoRowView(title: "状态")

    // 打卡
    private lazy var clockInButton = ActionButton(title: "上班打卡", symbol: "sun.max.fill", style: .primary, target: self, action: #selector(clockInTapped))
    private lazy var clockOutButton = ActionButton(title: "下班打卡", symbol: "moon.stars.fill", style: .primary, target: self, action: #selector(clockOutTapped))
    private lazy var undoButton = ActionButton(title: "撤销下班", symbol: "arrow.uturn.backward", style: .secondary, target: self, action: #selector(undoTapped))
    private lazy var targetMenu: NSPopUpButton = makeTargetMenu()

    // 今日记录
    private let recordHeaderLabel = UI.label("今日记录", font: Fonts.system(11, .semibold), color: .secondaryLabelColor)
    private let recordCountLabel = UI.label("", font: Fonts.system(10), color: .tertiaryLabelColor, alignment: .right)
    private let sessionStack = UI.verticalStack(spacing: 4)
    private lazy var correctionButton: NSButton = {
        let button = NSButton(title: "修正", target: self, action: #selector(correctFirstClockInTapped))
        button.bezelStyle = .rounded
        button.controlSize = .mini
        button.font = Fonts.system(10)
        button.toolTip = "修正今天首次打卡时间"
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    /// 弹出模态框时临时把 popover 设为常驻，避免编辑过程中面板自动收起。
    var onModalStateChange: ((Bool) -> Void)?

    private lazy var analysisButton = FooterButton(title: "分析", symbol: "chart.bar.xaxis", target: self, action: #selector(showAnalysis))
    private lazy var settingsButton = FooterButton(title: "设置", symbol: "gearshape", target: self, action: #selector(showSettings))
    private lazy var refreshHolidayButton = FooterButton(title: "更新节假日", symbol: "arrow.triangle.2.circlepath", target: self, action: #selector(refreshHolidays))
    private lazy var quitButton = FooterButton(title: "退出", symbol: "power", target: self, action: #selector(quitApp))

    init(store: AppStore, actions: AppActions?) {
        self.store = store
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()

        let stack = UI.verticalStack(spacing: 13)
        stack.alignment = .width
        root.addSubview(stack)
        let widthConstraint = root.widthAnchor.constraint(equalToConstant: 344)
        widthConstraint.priority = .required
        NSLayoutConstraint.activate([
            widthConstraint,
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Metrics.contentPadding),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Metrics.contentPadding),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: Metrics.contentPadding),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Metrics.contentPadding)
        ])

        buildHeader(into: stack)
        buildStatusCard(into: stack)
        buildActionRow(into: stack)
        buildRecordSection(into: stack)
        stack.addArrangedSubview(separator())
        buildFooter(into: stack)

        view = root
        refresh()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let size = view.fittingSize
        if preferredContentSize != size {
            preferredContentSize = size
        }
    }

    // MARK: - 构建

    private func buildHeader(into stack: NSStackView) {
        let row = UI.horizontalStack(spacing: 10)
        let left = UI.verticalStack(spacing: 3)
        left.addArrangedSubview(dateLabel)
        let badges = UI.horizontalStack(spacing: 6)
        demoBadge.text = "演示数据"
        demoBadge.tint = Theme.warningText
        demoBadge.isHidden = true
        badges.addArrangedSubview(demoBadge)
        badges.addArrangedSubview(offDayLabel)
        badges.addArrangedSubview(holidayLabel)
        left.addArrangedSubview(badges)
        row.addArrangedSubview(left)
        row.addArrangedSubview(UI.flexibleSpace())
        row.addArrangedSubview(statusPill)
        stack.addArrangedSubview(row)
    }

    private func buildStatusCard(into stack: NSStackView) {
        let card = CardView(padding: 14, spacing: 8)
        let row = UI.horizontalStack(spacing: 16, alignment: .centerY)

        let ringContainer = NSView()
        ringContainer.translatesAutoresizingMaskIntoConstraints = false
        ringContainer.addSubview(ringView)
        ringContainer.addSubview(ringValueLabel)
        ringContainer.addSubview(ringCaptionLabel)
        NSLayoutConstraint.activate([
            ringView.widthAnchor.constraint(equalToConstant: 92),
            ringView.heightAnchor.constraint(equalToConstant: 92),
            ringContainer.widthAnchor.constraint(equalToConstant: 92),
            ringContainer.heightAnchor.constraint(equalToConstant: 92),
            ringView.leadingAnchor.constraint(equalTo: ringContainer.leadingAnchor),
            ringView.trailingAnchor.constraint(equalTo: ringContainer.trailingAnchor),
            ringView.topAnchor.constraint(equalTo: ringContainer.topAnchor),
            ringView.bottomAnchor.constraint(equalTo: ringContainer.bottomAnchor),
            ringValueLabel.centerXAnchor.constraint(equalTo: ringContainer.centerXAnchor),
            ringCaptionLabel.centerXAnchor.constraint(equalTo: ringContainer.centerXAnchor),
            ringValueLabel.centerYAnchor.constraint(equalTo: ringContainer.centerYAnchor, constant: -8),
            ringCaptionLabel.topAnchor.constraint(equalTo: ringValueLabel.bottomAnchor, constant: 1)
        ])

        let info = UI.verticalStack(spacing: 7)
        info.addArrangedSubview(targetRow)
        info.addArrangedSubview(secondRow)
        info.addArrangedSubview(lunchRow)
        info.addArrangedSubview(statusRow)

        row.addArrangedSubview(ringContainer)
        row.addArrangedSubview(info)
        card.contentStack.addArrangedSubview(row)
        stack.addArrangedSubview(card)
    }

    private func buildActionRow(into stack: NSStackView) {
        let row = UI.horizontalStack(spacing: 8)
        row.addArrangedSubview(clockInButton)
        row.addArrangedSubview(clockOutButton)
        row.addArrangedSubview(undoButton)
        stack.addArrangedSubview(row)
        stack.addArrangedSubview(targetMenu)
    }

    private func buildRecordSection(into stack: NSStackView) {
        let header = UI.horizontalStack(spacing: 8)
        header.addArrangedSubview(recordHeaderLabel)
        header.addArrangedSubview(UI.flexibleSpace())
        header.addArrangedSubview(correctionButton)
        header.addArrangedSubview(recordCountLabel)
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(sessionStack)
    }

    private func buildFooter(into stack: NSStackView) {
        let footer = UI.horizontalStack(spacing: 6, alignment: .centerY)
        footer.distribution = .fillEqually
        footer.addArrangedSubview(analysisButton)
        footer.addArrangedSubview(settingsButton)
        footer.addArrangedSubview(refreshHolidayButton)
        footer.addArrangedSubview(quitButton)
        stack.addArrangedSubview(footer)
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    private func makeTargetMenu() -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.isBordered = false
        popup.controlSize = .small
        popup.font = Fonts.system(11)
        popup.target = self
        popup.action = #selector(targetMenuChanged(_:))
        popup.translatesAutoresizingMaskIntoConstraints = false
        let menu = NSMenu()
        let reset = NSMenuItem(title: "沿用默认目标（\(DurationFormat.text(store.settings.dailyTargetSeconds))）", action: nil, keyEquivalent: "")
        reset.tag = -1
        menu.addItem(reset)
        menu.addItem(.separator())
        for hours in [6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 10.0, 12.0] {
            let item = NSMenuItem(
                title: "今天设为 \(DurationFormat.text(hours * 3600))",
                action: nil,
                keyEquivalent: ""
            )
            item.tag = Int(hours * 2)
            menu.addItem(item)
        }
        popup.menu = menu
        return popup
    }

    // MARK: - 刷新

    func refresh() {
        dateLabel.stringValue = store.dayTitle
        offDayLabel.isHidden = !store.todayIsOffDay
        demoBadge.isHidden = !store.isDemoMode
        holidayLabel.isHidden = store.todayHoliday == nil
        holidayLabel.stringValue = store.todayHoliday?.name ?? ""

        if store.isWorking {
            statusPill.text = store.activeEntry?.dateKey == store.todayKey ? "上班中" : "上班中 · 跨天"
            statusPill.tint = Theme.accent
        } else if store.hasTodayRecords {
            statusPill.text = store.todayTargetSeconds > 0 && store.todayWorkedSeconds >= store.todayTargetSeconds ? "已达标" : "已下班"
            statusPill.tint = store.todayTargetSeconds > 0 && store.todayWorkedSeconds >= store.todayTargetSeconds
                ? Theme.teal
                : Theme.warning
        } else {
            statusPill.text = store.todayIsOffDay ? "休息日" : "未打卡"
            statusPill.tint = .secondaryLabelColor
        }

        ringView.progress = store.todayProgress
        let hasRecord = store.hasTodayRecords || store.isWorking
        ringValueLabel.stringValue = hasRecord ? DurationFormat.compact(store.todayWorkedSeconds) : "--:--"
        ringCaptionLabel.stringValue = hasRecord ? "已工作" : "尚未打卡"

        targetRow.value = DurationFormat.text(store.todayTargetSeconds)
        if store.isWorking {
            secondRow.update(title: "剩余", value: store.todayTargetSeconds > 0 ? DurationFormat.text(store.remainingSeconds) : "已达标")
        } else {
            secondRow.update(title: "完成度", value: "\(Int((store.todayProgress * 100).rounded()))%")
        }
        statusRow.value = store.statusSubtitle
        let lunch = store.settings.lunchBreak
        lunchRow.isHidden = !lunch.isEnabled
        if lunch.isEnabled {
            let deducted = store.todayLunchSeconds
            lunchRow.update(
                title: "午休 \(lunch.displayText)",
                value: deducted > 0 ? "−\(DurationFormat.text(deducted))" : "0 分"
            )
        }

        clockInButton.isHidden = store.isWorking
        clockOutButton.isHidden = !store.isWorking
        undoButton.isHidden = !store.canUndoClockOut
        undoButton.toolTip = "回来加班时，撤销最近一次下班打卡，恢复上班状态"

        targetMenu.selectItem(withTag: -1)
        targetMenu.title = "今日目标：\(DurationFormat.text(store.todayTargetSeconds))"

        rebuildSessions()
    }

    private func rebuildSessions() {
        sessionStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        recordCountLabel.stringValue = "\(store.todaySessions.count) 段"
        correctionButton.isHidden = store.todaySessions.isEmpty
        if let first = store.todaySessions.first {
            correctionButton.toolTip = "当前首次打卡 \(UI.time(first.start, calendar: store.calendar))，点击修正"
        }

        guard !store.todaySessions.isEmpty else {
            let empty = UI.label(
                store.todayIsOffDay ? "今天是休息日，暂无记录" : "今天还没有打卡记录",
                font: Fonts.system(12),
                color: .tertiaryLabelColor,
                alignment: .center
            )
            sessionStack.addArrangedSubview(empty)
            return
        }

        for session in store.todaySessions {
            sessionStack.addArrangedSubview(makeSessionRow(session))
        }
    }

    private func makeSessionRow(_ session: WorkSession) -> NSView {
        let row = UI.horizontalStack(spacing: 8, alignment: .centerY)

        let icon = NSImageView()
        icon.image = UI.symbolImage(session.startSource.symbolName, size: 11, weight: .medium)
        icon.contentTintColor = session.startSource.tintColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true

        let textStack = UI.verticalStack(spacing: 1)
        let timeText = "\(UI.time(session.start, calendar: store.calendar)) – \(session.end.map { UI.time($0, calendar: store.calendar) } ?? "进行中")"
        textStack.addArrangedSubview(UI.label(timeText, font: Fonts.system(12)))
        let sourceText = session.endSource.map { "\($0.shortName)记录" } ?? "进行中"
        textStack.addArrangedSubview(UI.label(sourceText, font: Fonts.system(9.5), color: .secondaryLabelColor))

        let duration = UI.label(
            DurationFormat.compact(session.duration(until: store.now)),
            font: Fonts.mono(12, .medium),
            alignment: .right
        )
        duration.textColor = session.isActive ? Theme.accent : .secondaryLabelColor

        row.addArrangedSubview(icon)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(UI.flexibleSpace())
        row.addArrangedSubview(duration)
        return row
    }

    // MARK: - 动作

    @objc private func clockInTapped() {
        store.clockIn()
    }

    @objc private func clockOutTapped() {
        store.clockOut()
    }

    @objc private func undoTapped() {
        store.undoLastClockOut()
    }

    @objc private func targetMenuChanged(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        if item.tag == -1 {
            store.setTodayTarget(hours: nil)
        } else {
            store.setTodayTarget(hours: Double(item.tag) / 2)
        }
    }

    /// 修正今天首次打卡时间（例如补录成 09:28）。
    @objc private func correctFirstClockInTapped() {
        guard let first = store.todaySessions.first else { return }
        onModalStateChange?(true)
        defer { onModalStateChange?(false) }

        let alert = NSAlert()
        alert.messageText = "修正今天首次打卡时间"
        alert.informativeText = "当前记录为 \(UI.time(first.start, calendar: store.calendar))，选择新的上班时间："
        alert.alertStyle = .informational

        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.dateValue = first.start
        picker.maxDate = Date()
        picker.frame = NSRect(x: 0, y: 0, width: 240, height: 26)
        alert.accessoryView = picker
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            store.correctFirstClockIn(ofDayKey: store.todayKey, to: picker.dateValue)
        }
    }

    @objc private func showAnalysis() {
        actions?.showAnalysis()
    }

    @objc private func showSettings() {
        actions?.showSettings()
    }

    @objc private func refreshHolidays() {
        Task { await store.refreshHolidays() }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
