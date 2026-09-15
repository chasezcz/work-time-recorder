import AppKit
import Combine
import WorkTimeCore

/// 统计页：周期切换、汇总卡片、图表与每日明细。
@MainActor
final class StatisticsViewController: NSViewController {
    private let store: AppStore
    private var offset = 0
    private var cancellable: AnyCancellable?

    private lazy var granularityControl: NSSegmentedControl = {
        let control = NSSegmentedControl(
            labels: PeriodGranularity.allCases.map(\.title),
            trackingMode: .selectOne,
            target: self,
            action: #selector(granularityChanged(_:))
        )
        control.selectedSegment = 1
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private lazy var previousButton = makeStepperButton(symbol: "chevron.left", action: #selector(previousPeriod))
    private lazy var nextButton = makeStepperButton(symbol: "chevron.right", action: #selector(nextPeriod))
    private let periodLabel = UI.label("", font: Fonts.system(15, .semibold))
    private lazy var todayButton: NSButton = {
        let button = NSButton(title: "回到今天", target: self, action: #selector(resetPeriod))
        button.isBordered = false
        button.contentTintColor = Theme.accent
        button.font = Fonts.system(12, .medium)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let workedCard = StatCardView(title: "累计工时", symbol: "clock", tint: Theme.accent)
    private let targetCard = StatCardView(title: "目标工时", symbol: "target", tint: Theme.teal)
    private let completionCard = StatCardView(title: "完成度", symbol: "chart.line.uptrend.xyaxis", tint: Theme.teal)
    private let overtimeCard = StatCardView(title: "加班时长", symbol: "flame", tint: Theme.warning)

    private let chartTitleLabel = UI.label("", font: Fonts.system(13, .semibold))
    private let chartView = BarChartView()
    private let timelineView = DayTimelineView()
    private let timelineStack = UI.verticalStack(spacing: 6)
    private let dayListStack = UI.verticalStack(spacing: 0)
    private let dayListHint = UI.label("", font: Fonts.system(11), color: .secondaryLabelColor)

    init(store: AppStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()

        let controls = UI.horizontalStack(spacing: 10, alignment: .centerY)
        controls.addArrangedSubview(granularityControl)
        controls.addArrangedSubview(previousButton)
        controls.addArrangedSubview(periodLabel)
        controls.addArrangedSubview(nextButton)
        controls.addArrangedSubview(todayButton)
        controls.addArrangedSubview(UI.flexibleSpace())

        root.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            controls.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            controls.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            granularityControl.widthAnchor.constraint(equalToConstant: 250),
            periodLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 14),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        let content = UI.verticalStack(spacing: 16)
        content.alignment = .width
        documentView.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 2),
            content.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -20),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor)
        ])

        content.addArrangedSubview(makeCardsRow())
        content.addArrangedSubview(makeChartCard())
        content.addArrangedSubview(makeDayListCard())

        view = root
        refresh()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        cancellable = store.observe { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - 构建

    private func makeCardsRow() -> NSView {
        let row = UI.horizontalStack(spacing: 12, alignment: .top)
        row.distribution = .fillEqually
        row.addArrangedSubview(workedCard)
        row.addArrangedSubview(targetCard)
        row.addArrangedSubview(completionCard)
        row.addArrangedSubview(overtimeCard)
        return row
    }

    private func makeChartCard() -> NSView {
        let card = CardView(padding: 14, spacing: 10)
        card.contentStack.addArrangedSubview(chartTitleLabel)

        chartView.translatesAutoresizingMaskIntoConstraints = false
        chartView.heightAnchor.constraint(equalToConstant: 250).isActive = true
        card.contentStack.addArrangedSubview(chartView)

        timelineView.translatesAutoresizingMaskIntoConstraints = false
        timelineView.heightAnchor.constraint(equalToConstant: 46).isActive = true
        card.contentStack.addArrangedSubview(timelineView)
        card.contentStack.addArrangedSubview(timelineStack)
        return card
    }

    private func makeDayListCard() -> NSView {
        let card = CardView(padding: 14, spacing: 8)
        let header = UI.horizontalStack(spacing: 8)
        header.addArrangedSubview(UI.label("每日明细", font: Fonts.system(13, .semibold)))
        header.addArrangedSubview(UI.flexibleSpace())
        header.addArrangedSubview(dayListHint)
        card.contentStack.addArrangedSubview(header)
        card.contentStack.addArrangedSubview(dayListStack)
        return card
    }

    private func makeStepperButton(symbol: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = UI.symbolImage(symbol, size: 12, weight: .semibold)
        button.isBordered = false
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    // MARK: - 刷新

    private var granularity: PeriodGranularity {
        let index = max(0, min(granularityControl.selectedSegment, PeriodGranularity.allCases.count - 1))
        return PeriodGranularity.allCases[index]
    }

    private func refresh() {
        let stats = store.periodStats(granularity: granularity, offset: offset)
        store.ensureHolidaysLoaded(forInterval: stats.interval)

        periodLabel.stringValue = AppCalendar.describe(stats.interval, granularity: granularity)
        todayButton.isHidden = offset == 0
        nextButton.isHidden = offset == 0

        workedCard.update(value: DurationFormat.text(stats.totalWorkedSeconds), caption: "打卡 \(stats.activeDayCount) 天")
        targetCard.update(value: DurationFormat.text(stats.totalTargetSeconds), caption: "\(stats.requiredDayCount) 个工作日")
        completionCard.update(
            value: "\(Int((stats.completionRatio * 100).rounded()))%",
            caption: stats.isTargetReached
                ? "已达标"
                : "还差 \(DurationFormat.text(max(0, stats.totalTargetSeconds - stats.totalWorkedSeconds)))"
        )
        overtimeCard.update(
            value: DurationFormat.text(stats.overtimeSeconds),
            caption: stats.activeDayCount > 0 ? "平均每天 \(DurationFormat.text(stats.averageSecondsPerActiveDay))" : "暂无记录"
        )

        let isDay = granularity == .day
        chartTitleLabel.stringValue = isDay
            ? "今天时间轴（\(store.workdayWindowText)）"
            : granularity.chartTitle
        chartView.isHidden = isDay
        timelineView.isHidden = !isDay
        timelineStack.isHidden = !isDay

        if isDay {
            let window = store.todayWorkdayWindow
            let entries = store.ledger.sessions(in: window, now: store.now)
            timelineView.calendar = store.calendar
            timelineView.interval = window
            timelineView.segments = entries.map { (start: $0.start, end: $0.end) }
            rebuildTimelineRows(entries)
        } else {
            chartView.data = stats.buckets.map { bucket in
                let regular = bucket.targetSeconds > 0 ? min(bucket.workedSeconds, bucket.targetSeconds) : bucket.workedSeconds
                return BarChartDatum(
                    title: bucket.title,
                    regularHours: regular / 3600,
                    overtimeHours: max(0, bucket.workedSeconds - regular) / 3600,
                    targetHours: bucket.targetHours,
                    isCurrent: bucket.isCurrent,
                    isOffDay: bucket.isOffDay
                )
            }
        }

        rebuildDayList(stats)
    }

    private func rebuildTimelineRows(_ entries: [(dateKey: String, session: WorkSession, start: Date, end: Date)]) {
        timelineStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !entries.isEmpty else {
            timelineStack.addArrangedSubview(
                UI.label("这一天没有打卡记录", font: Fonts.system(12), color: .tertiaryLabelColor)
            )
            return
        }
        for entry in entries {
            let row = UI.horizontalStack(spacing: 10, alignment: .centerY)
            let icon = NSImageView()
            icon.image = UI.symbolImage(entry.session.startSource.symbolName, size: 11)
            icon.contentTintColor = entry.session.startSource.tintColor
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 16).isActive = true

            let session = entry.session
            let range = "\(UI.time(session.start, calendar: store.calendar)) – \(session.end.map { UI.time($0, calendar: store.calendar) } ?? "进行中")"
            let source = entry.session.endSource.map { "· \($0.shortName)" } ?? "· 进行中"
            row.addArrangedSubview(icon)
            row.addArrangedSubview(UI.label(range, font: Fonts.system(12)))
            row.addArrangedSubview(UI.label(source, font: Fonts.system(11), color: .secondaryLabelColor))
            row.addArrangedSubview(UI.flexibleSpace())
            row.addArrangedSubview(
                UI.label(DurationFormat.text(session.duration(until: store.now)), font: Fonts.mono(12, .medium), alignment: .right)
            )
            timelineStack.addArrangedSubview(row)
        }
    }

    private func rebuildDayList(_ stats: PeriodStats) {
        dayListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let rows = granularity == .day ? stats.days : stats.days.filter { $0.hasRecords || $0.isFuture == false }
        let missing = stats.days.filter { !$0.hasRecords && !$0.isOffDay && !$0.isFuture }.count
        dayListHint.stringValue = missing > 0 ? "有 \(missing) 个工作日没有打卡记录" : ""

        guard !rows.isEmpty else {
            dayListStack.addArrangedSubview(
                UI.label("当前周期还没有打卡记录", font: Fonts.system(12), color: .tertiaryLabelColor)
            )
            return
        }

        for (index, day) in rows.enumerated() {
            dayListStack.addArrangedSubview(makeDayRow(day))
            if index != rows.count - 1 {
                let separator = NSBox()
                separator.boxType = .separator
                separator.translatesAutoresizingMaskIntoConstraints = false
                dayListStack.addArrangedSubview(separator)
            }
        }
    }

    private func makeDayRow(_ day: DayStat) -> NSView {
        let row = UI.horizontalStack(spacing: 12, alignment: .centerY)

        let left = UI.verticalStack(spacing: 2)
        let titleRow = UI.horizontalStack(spacing: 6)
        titleRow.addArrangedSubview(UI.label(AppCalendar.dayLabel(day.date, calendar: store.calendar), font: Fonts.system(12.5, .medium)))
        titleRow.addArrangedSubview(UI.label(AppCalendar.weekdayName(day.date, calendar: store.calendar), font: Fonts.system(11), color: .secondaryLabelColor))
        if let holiday = day.holidayName {
            titleRow.addArrangedSubview(makeBadge(holiday, color: Theme.warningText))
        }
        left.addArrangedSubview(titleRow)
        left.addArrangedSubview(
            UI.label(
                day.firstClockIn.map { "\(UI.time($0, calendar: store.calendar)) 上班" } ?? "—",
                font: Fonts.system(10),
                color: .tertiaryLabelColor
            )
        )

        let status = dayStatus(day)

        row.addArrangedSubview(left)
        row.addArrangedSubview(UI.flexibleSpace())
        row.addArrangedSubview(UI.label(day.sessionCount > 0 ? "\(day.sessionCount) 段" : "", font: Fonts.system(11), color: .secondaryLabelColor, alignment: .right))
        let worked = UI.label(DurationFormat.text(day.workedSeconds), font: Fonts.mono(12.5, .medium), alignment: .right)
        worked.widthAnchor.constraint(equalToConstant: 110).isActive = true
        row.addArrangedSubview(worked)
        let target = UI.label(day.targetSeconds > 0 ? "/ \(DurationFormat.text(day.targetSeconds))" : "", font: Fonts.system(10.5), color: .tertiaryLabelColor, alignment: .right)
        target.widthAnchor.constraint(equalToConstant: 100).isActive = true
        row.addArrangedSubview(target)
        let statusLabel = UI.label(status.text, font: Fonts.system(11, .medium), color: status.color, alignment: .right)
        statusLabel.widthAnchor.constraint(equalToConstant: 78).isActive = true
        row.addArrangedSubview(statusLabel)
        return row
    }

    private func makeBadge(_ text: String, color: NSColor) -> NSView {
        let badge = StatusPillView()
        badge.text = text
        badge.tint = color
        return badge
    }

    private func dayStatus(_ day: DayStat) -> (text: String, color: NSColor) {
        if day.isFuture { return ("未开始", .tertiaryLabelColor) }
        if !day.hasRecords { return (day.isOffDay ? "休息" : "无记录", .tertiaryLabelColor) }
        if day.targetSeconds == 0 { return ("休息日加班", Theme.teal) }
        return day.workedSeconds >= day.targetSeconds ? ("已达标", Theme.teal) : ("未达标", Theme.warningText)
    }

    // MARK: - 动作

    @objc private func granularityChanged(_ sender: NSSegmentedControl) {
        offset = 0
        refresh()
    }

    @objc private func previousPeriod() {
        offset = max(offset - 1, -600)
        refresh()
    }

    @objc private func nextPeriod() {
        offset = min(offset + 1, 0)
        refresh()
    }

    @objc private func resetPeriod() {
        offset = 0
        refresh()
    }
}
