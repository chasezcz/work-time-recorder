import AppKit

/// 工时分析窗口：统计 / 节假日 / 导出。
@MainActor
final class AnalysisWindowController: NSWindowController {
    init(store: AppStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "工时分析"
        window.minSize = NSSize(width: 920, height: 620)
        window.contentViewController = AnalysisTabViewController(store: store)
        window.setContentSize(NSSize(width: 980, height: 700))
        window.center()
        window.setFrameAutosaveName("WorkTimeAnalysisWindow")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

/// 顶部标签 + 内容容器。
@MainActor
final class AnalysisTabViewController: NSViewController {
    private let store: AppStore
    private lazy var segmented: NSSegmentedControl = {
        let control = NSSegmentedControl(
            labels: ["统计", "节假日", "导出"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(segmentChanged(_:))
        )
        control.selectedSegment = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private lazy var pages: [NSViewController] = [
        StatisticsViewController(store: store),
        HolidayViewController(store: store),
        ExportViewController(store: store)
    ]

    private let container = NSView()
    private var currentIndex = -1

    init(store: AppStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(segmented)
        root.addSubview(container)
        NSLayoutConstraint.activate([
            segmented.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            segmented.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 12),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        view = root
        show(index: 0)
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        show(index: sender.selectedSegment)
    }

    private func show(index: Int) {
        guard index >= 0, index < pages.count, index != currentIndex else { return }
        if currentIndex >= 0 {
            let previous = pages[currentIndex]
            previous.view.removeFromSuperview()
            previous.removeFromParent()
        }
        currentIndex = index
        let page = pages[index]
        addChild(page)
        let pageView = page.view
        pageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            pageView.topAnchor.constraint(equalTo: container.topAnchor),
            pageView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}
