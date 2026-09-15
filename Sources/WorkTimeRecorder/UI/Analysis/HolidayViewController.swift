import AppKit
import Combine
import WorkTimeCore

/// 节假日页：按年份查看、手动更新、展示放假与调休补班。
@MainActor
final class HolidayViewController: NSViewController {
    private let store: AppStore
    private var year: Int
    private var cancellable: AnyCancellable?

    private let yearLabel = UI.label("", font: Fonts.system(16, .semibold))
    private let statusLabel = UI.label("", font: Fonts.system(11), color: .secondaryLabelColor)
    private lazy var previousButton = NSButton(title: "‹", target: self, action: #selector(previousYear))
    private lazy var nextButton = NSButton(title: "›", target: self, action: #selector(nextYear))
    private lazy var refreshButton = NSButton(title: "立即更新", target: self, action: #selector(refreshNow))
    private let scrollView = NSScrollView()
    private let contentStack = UI.verticalStack(spacing: 12)

    init(store: AppStore) {
        self.store = store
        self.year = store.calendar.component(.year, from: Date())
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()

        previousButton.isBordered = false
        nextButton.isBordered = false
        previousButton.font = Fonts.system(18, .semibold)
        nextButton.font = Fonts.system(18, .semibold)
        refreshButton.bezelStyle = .rounded
        refreshButton.controlSize = .small

        let controls = UI.horizontalStack(spacing: 10, alignment: .centerY)
        controls.addArrangedSubview(previousButton)
        controls.addArrangedSubview(yearLabel)
        controls.addArrangedSubview(nextButton)
        controls.addArrangedSubview(UI.flexibleSpace())
        controls.addArrangedSubview(statusLabel)
        controls.addArrangedSubview(refreshButton)

        root.addSubview(controls)
        contentStack.alignment = .width
        let scrollView = ScrollContainer.make(
            content: contentStack,
            horizontalPadding: 20,
            topPadding: 2,
            bottomPadding: 20
        )
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            controls.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            controls.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        view = root
        refresh()
        ensureLoaded()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        cancellable = store.observe { [weak self] in
            self?.refresh()
        }
    }

    private func ensureLoaded() {
        store.ensureHolidaysLoaded(forInterval: yearInterval())
    }

    private func yearInterval() -> DateInterval {
        let middle = store.calendar.date(from: DateComponents(year: year, month: 6, day: 1)) ?? Date()
        return AppCalendar.interval(for: .year, containing: middle, calendar: store.calendar)
    }

    // MARK: - 刷新

    private func refresh() {
        yearLabel.stringValue = "\(year) 年"
        statusLabel.stringValue = statusText()
        refreshButton.isHidden = store.holidayState == .loading

        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let holidays = store.holidays(year: year)
        if holidays.isEmpty {
            contentStack.addArrangedSubview(emptyState())
            return
        }

        let groups = Dictionary(grouping: holidays) { String($0.date.prefix(7)) }
        for key in groups.keys.sorted() {
            let month = Int(key.suffix(2)).map { "\($0) 月" } ?? key
            contentStack.addArrangedSubview(UI.label(month, font: Fonts.system(13, .semibold)))
            for holiday in groups[key]!.sorted(by: { $0.date < $1.date }) {
                contentStack.addArrangedSubview(makeHolidayRow(holiday))
            }
        }
    }

    private func statusText() -> String {
        if case .loading = store.holidayState { return "正在从公开 API 更新…" }
        if case .failed(let message) = store.holidayState { return "更新失败：\(message)" }
        if let date = store.lastHolidayRefresh(year: year) {
            return "缓存更新于 \(AppCalendar.formatter("MM-dd HH:mm").string(from: date))"
        }
        return store.holidays(year: year).isEmpty ? "暂无缓存" : "使用本地缓存"
    }

    private func makeHolidayRow(_ holiday: HolidayDay) -> NSView {
        let row = UI.horizontalStack(spacing: 10, alignment: .centerY)
        row.addArrangedSubview(UI.label(String(holiday.date.suffix(5)), font: Fonts.mono(12, .medium)))
        row.addArrangedSubview(UI.label(holiday.name, font: Fonts.system(12.5)))
        row.addArrangedSubview(UI.flexibleSpace())

        if holiday.isOffDay {
            row.addArrangedSubview(makeBadge("放假", color: Theme.teal))
        } else {
            row.addArrangedSubview(makeBadge("调休补班", color: Theme.warningText))
        }
        row.addArrangedSubview(UI.label(holiday.source, font: Fonts.system(10), color: .tertiaryLabelColor))

        let container = CardView(padding: 10, cornerRadius: 8, spacing: 0)
        container.contentStack.addArrangedSubview(row)
        return container
    }

    private func makeBadge(_ text: String, color: NSColor) -> StatusPillView {
        let badge = StatusPillView()
        badge.text = text
        badge.tint = color
        return badge
    }

    private func emptyState() -> NSView {
        let stack = UI.verticalStack(spacing: 10)
        stack.alignment = .centerX
        stack.addArrangedSubview(UI.label("还没有 \(year) 年的节假日数据", font: Fonts.system(14, .semibold)))
        stack.addArrangedSubview(
            UI.multilineLabel("点击右上角“立即更新”从公开节假日 API 拉取，成功后会缓存在本地。", font: Fonts.system(11))
        )
        return stack
    }

    // MARK: - 动作

    @objc private func previousYear() {
        year -= 1
        ensureLoaded()
        refresh()
    }

    @objc private func nextYear() {
        year += 1
        ensureLoaded()
        refresh()
    }

    @objc private func refreshNow() {
        Task { await store.refreshHolidays(years: [year]) }
    }
}
