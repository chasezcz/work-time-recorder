import AppKit
import WorkTimeCore

/// 圆角卡片容器：内部自带垂直堆栈与内边距。
final class CardView: NSView {
    let contentStack: NSStackView

    private let padding: CGFloat
    private let cornerRadius: CGFloat

    init(padding: CGFloat = Metrics.cardPadding, cornerRadius: CGFloat = Metrics.cornerRadius, spacing: CGFloat = 8) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.contentStack = UI.verticalStack(spacing: spacing)
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Theme.cardBackground.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// 状态胶囊标签，例如“上班中”“已达标”。
final class StatusPillView: NSView {
    private let label = UI.label("", font: Fonts.system(11, .semibold))

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    var tint: NSColor = .secondaryLabelColor {
        didSet {
            label.textColor = tint
            needsDisplay = true
        }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = tint.withAlphaComponent(0.16).cgColor
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// “标签 —— 值” 的信息行。
final class InfoRowView: NSView {
    private let titleLabel: NSTextField
    private let valueLabel: NSTextField

    init(title: String, value: String = "", valueFont: NSFont = Fonts.mono(13, .medium)) {
        titleLabel = UI.label(title, font: Fonts.system(12), color: .secondaryLabelColor)
        valueLabel = UI.label(value, font: valueFont, alignment: .right)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = UI.horizontalStack(spacing: 8, alignment: .firstBaseline)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(UI.flexibleSpace())
        stack.addArrangedSubview(valueLabel)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    var value: String {
        get { valueLabel.stringValue }
        set { valueLabel.stringValue = newValue }
    }

    func update(title: String? = nil, value: String) {
        if let title { titleLabel.stringValue = title }
        valueLabel.stringValue = value
    }
}

/// 统计卡片：标题 + 大号数值 + 说明。
final class StatCardView: NSView {
    private let titleLabel: NSTextField
    private let valueLabel: NSTextField
    private let captionLabel: NSTextField
    private let iconView = NSImageView()

    init(title: String, symbol: String, tint: NSColor) {
        titleLabel = UI.label(title, font: Fonts.system(11), color: .secondaryLabelColor)
        valueLabel = UI.label("—", font: Fonts.rounded(20, .semibold))
        captionLabel = UI.label("", font: Fonts.system(10), color: .tertiaryLabelColor)
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        iconView.image = UI.symbolImage(symbol, size: 11, weight: .semibold)
        iconView.contentTintColor = tint
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleRow = UI.horizontalStack(spacing: 5)
        titleRow.addArrangedSubview(iconView)
        titleRow.addArrangedSubview(titleLabel)
        titleRow.addArrangedSubview(UI.flexibleSpace())

        let stack = UI.verticalStack(spacing: 5)
        stack.addArrangedSubview(titleRow)
        stack.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(captionLabel)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(value: String, caption: String?) {
        valueLabel.stringValue = value
        captionLabel.stringValue = caption ?? ""
        captionLabel.isHidden = caption == nil
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Theme.cardBackground.cgColor
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// 主要/次要操作按钮，统一圆角与悬停反馈。
final class ActionButton: NSButton {
    enum Style {
        case primary
        case secondary
        case danger
    }

    private let style: Style
    private var isHovering = false
    private let gradientLayer = CAGradientLayer()

    init(title: String, symbol: String? = nil, style: Style, target: AnyObject? = nil, action: Selector? = nil) {
        self.style = style
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        focusRingType = .none

        let textColor: NSColor
        switch style {
        case .primary: textColor = .white
        case .secondary: textColor = .labelColor
        case .danger: textColor = Theme.danger
        }
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: Fonts.system(12.5, .semibold),
            .foregroundColor: textColor
        ])

        if let symbol, let image = UI.symbolImage(symbol, size: 12, weight: .semibold) {
            self.image = image
            imagePosition = .imageLeading
            contentTintColor = textColor
        }

        if style == .primary {
            gradientLayer.colors = Theme.progressColors.map(\.cgColor)
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            gradientLayer.cornerRadius = 9
            layer?.insertSublayer(gradientLayer, at: 0)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }

    override func updateLayer() {
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        switch style {
        case .primary:
            layer?.backgroundColor = nil
            gradientLayer.opacity = isHovering ? 0.88 : 1
        case .secondary:
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(isHovering ? 0.16 : 0.08).cgColor
        case .danger:
            layer?.backgroundColor = Theme.danger.withAlphaComponent(isHovering ? 0.22 : 0.12).cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }
}

/// 底部图标按钮：图标在上、文字在下。
final class FooterButton: NSButton {
    private var isHovering = false

    init(title: String, symbol: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        image = UI.symbolImage(symbol, size: 13, weight: .medium)
        imagePosition = .imageAbove
        imageScaling = .scaleProportionallyDown
        font = Fonts.system(10)
        contentTintColor = .secondaryLabelColor
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: Fonts.system(10),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        focusRingType = .none
        heightAnchor.constraint(equalToConstant: 42).isActive = true
        toolTip = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(isHovering ? 0.09 : 0).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }
}

/// 分组标题。
func makeSectionHeader(_ text: String) -> NSTextField {
    UI.label(text, font: Fonts.system(12, .semibold), color: .secondaryLabelColor)
}

/// 翻转坐标系的容器，适合作为滚动视图的文档视图（内容从顶部开始）。
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 生成带垂直滚动的容器：内容高度自由增长，不会撑大外层窗口。
enum ScrollContainer {
    static func make(
        content: NSView,
        horizontalPadding: CGFloat = 20,
        topPadding: CGFloat = 16,
        bottomPadding: CGFloat = 24
    ) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        documentView.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: horizontalPadding),
            content.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -horizontalPadding),
            content.topAnchor.constraint(equalTo: documentView.topAnchor, constant: topPadding),
            content.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -bottomPadding),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor)
        ])
        return scrollView
    }
}

extension ClockSource {
    var tintColor: NSColor {
        switch self {
        case .manual: return Theme.accent
        case .autoUnlock: return Theme.teal
        case .autoLock: return Theme.warning
        }
    }
}
