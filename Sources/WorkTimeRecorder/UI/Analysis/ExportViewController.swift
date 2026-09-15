import AppKit
import UniformTypeIdentifiers
import WorkTimeCore

/// 导出页：选择范围，导出打卡明细或每日汇总 CSV。
@MainActor
final class ExportViewController: NSViewController {
    private let store: AppStore
    private var preset: ExportPreset = .thisMonth

    private lazy var presetControl: NSSegmentedControl = {
        let control = NSSegmentedControl(
            labels: ExportPreset.allCases.map(\.title),
            trackingMode: .selectOne,
            target: self,
            action: #selector(presetChanged(_:))
        )
        control.selectedSegment = ExportPreset.allCases.firstIndex(of: .thisMonth) ?? 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private let dayCard = StatCardView(title: "打卡天数", symbol: "calendar", tint: Theme.accent)
    private let sessionCard = StatCardView(title: "打卡段数", symbol: "list.bullet", tint: Theme.teal)
    private let hoursCard = StatCardView(title: "累计工时", symbol: "clock", tint: Theme.warning)
    private lazy var detailButton = ActionButton(
        title: "导出打卡明细 CSV",
        symbol: "square.and.arrow.up",
        style: .primary,
        target: self,
        action: #selector(exportDetail)
    )
    private lazy var summaryButton = ActionButton(
        title: "导出每日汇总 CSV",
        symbol: "tablecells",
        style: .secondary,
        target: self,
        action: #selector(exportSummary)
    )
    private let messageLabel = UI.label("", font: Fonts.system(12))
    private let hintLabel = UI.multilineLabel(
        "CSV 使用 UTF-8（含 BOM）编码，Excel 与 Numbers 可直接打开。明细包含每一段打卡的上下班方式；汇总按天给出目标、实际、差额与完成度。",
        font: Fonts.system(10.5)
    )

    init(store: AppStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        let header = UI.verticalStack(spacing: 8)
        header.addArrangedSubview(UI.label("导出范围", font: Fonts.system(14, .semibold)))
        header.addArrangedSubview(presetControl)
        presetControl.widthAnchor.constraint(equalToConstant: 420).isActive = true

        let cards = UI.horizontalStack(spacing: 12, alignment: .top)
        cards.distribution = .fillEqually
        cards.addArrangedSubview(dayCard)
        cards.addArrangedSubview(sessionCard)
        cards.addArrangedSubview(hoursCard)

        let buttons = UI.horizontalStack(spacing: 10, alignment: .centerY)
        detailButton.widthAnchor.constraint(equalToConstant: 220).isActive = true
        summaryButton.widthAnchor.constraint(equalToConstant: 220).isActive = true
        buttons.addArrangedSubview(detailButton)
        buttons.addArrangedSubview(summaryButton)

        let content = UI.verticalStack(spacing: 18)
        content.alignment = .leading
        content.addArrangedSubview(header)
        content.addArrangedSubview(cards)
        content.addArrangedSubview(buttons)
        content.addArrangedSubview(messageLabel)
        content.addArrangedSubview(hintLabel)

        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            cards.widthAnchor.constraint(equalTo: content.widthAnchor),
            hintLabel.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])

        view = root
        refresh()
    }

    private func refresh() {
        let preview = store.exportPreview(preset: preset)
        dayCard.update(value: "\(preview.days) 天", caption: nil)
        sessionCard.update(value: "\(preview.sessions) 段", caption: nil)
        hoursCard.update(
            value: DurationFormat.text(preview.workedSeconds),
            caption: "\(DurationFormat.decimalHours(preview.workedSeconds, fractionDigits: 2)) 小时"
        )
        messageLabel.stringValue = ""
    }

    @objc private func presetChanged(_ sender: NSSegmentedControl) {
        let index = max(0, min(sender.selectedSegment, ExportPreset.allCases.count - 1))
        preset = ExportPreset.allCases[index]
        refresh()
    }

    @objc private func exportDetail() {
        saveCSV(make: { [store] in store.sessionsCSV(preset: preset) }, prefix: "工时明细-\(preset.title)")
    }

    @objc private func exportSummary() {
        saveCSV(make: { [store] in store.summaryCSV(preset: preset) }, prefix: "工时汇总-\(preset.title)")
    }

    private func saveCSV(make: () -> String, prefix: String) {
        let panel = NSSavePanel()
        panel.title = "导出 CSV"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(prefix)-\(AppCalendar.formatter("yyyyMMdd-HHmm").string(from: Date())).csv"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let data = make().data(using: .utf8) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            try data.write(to: url, options: .atomic)
            messageLabel.textColor = Theme.teal
            messageLabel.stringValue = "已导出：\(url.lastPathComponent)"
        } catch {
            messageLabel.textColor = Theme.danger
            messageLabel.stringValue = "导出失败：\(error.localizedDescription)"
        }
    }
}
