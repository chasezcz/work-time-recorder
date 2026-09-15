import AppKit
import WorkTimeCore

/// 全局配色、字体与尺寸。
enum Theme {
    static let accent = NSColor(srgbRed: 0.35, green: 0.45, blue: 0.97, alpha: 1)
    static let accentSoft = NSColor(srgbRed: 0.56, green: 0.68, blue: 0.99, alpha: 1)
    static let teal = NSColor(srgbRed: 0.13, green: 0.78, blue: 0.72, alpha: 1)
    static let warning = NSColor(srgbRed: 0.97, green: 0.71, blue: 0.22, alpha: 1)
    static let warningText = NSColor(srgbRed: 0.76, green: 0.53, blue: 0.08, alpha: 1)
    static let danger = NSColor(srgbRed: 0.93, green: 0.35, blue: 0.35, alpha: 1)

    static let progressColors = [accent, teal]
    static let overtimeColors = [warning, NSColor(srgbRed: 0.98, green: 0.55, blue: 0.30, alpha: 1)]

    static let cardBackground = dynamic(
        light: NSColor(white: 0, alpha: 0.045),
        dark: NSColor(white: 1, alpha: 0.075)
    )
    static let controlBackground = dynamic(
        light: NSColor(white: 0, alpha: 0.08),
        dark: NSColor(white: 1, alpha: 0.12)
    )
    static let chartTrack = dynamic(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.10))
    static let gridLine = dynamic(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.10))

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

enum Fonts {
    static func system(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// 圆润数字字体，用于大号数值。
    static func rounded(_ size: CGFloat, _ weight: NSFont.Weight = .semibold) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let font = NSFont(descriptor: descriptor, size: size) else { return base }
        return font
    }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .medium) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
}

enum Metrics {
    static let cornerRadius: CGFloat = 14
    static let cardPadding: CGFloat = 14
    static let contentPadding: CGFloat = 16
}

/// 常用控件工厂。
enum UI {
    static func label(
        _ text: String = "",
        font: NSFont = Fonts.system(13),
        color: NSColor = .labelColor,
        alignment: NSTextAlignment = .left
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func verticalStack(spacing: CGFloat = 8, alignment: NSLayoutConstraint.Attribute = .width) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = spacing
        stack.alignment = alignment
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// 可自动换行的多行标签（需要父视图给定宽度）。
    static func multilineLabel(
        _ text: String,
        font: NSFont = Fonts.system(11),
        color: NSColor = .secondaryLabelColor
    ) -> NSTextField {
        let label = label(text, font: font, color: color)
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    static func horizontalStack(spacing: CGFloat = 8, alignment: NSLayoutConstraint.Attribute = .centerY) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = spacing
        stack.alignment = alignment
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// 水平方向可伸缩的占位视图。
    static func flexibleSpace() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    static func symbolImage(_ name: String, size: CGFloat = 13, weight: NSFont.Weight = .medium) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    static func time(_ date: Date, calendar: Calendar = AppCalendar.calendar()) -> String {
        AppCalendar.formatter("HH:mm", calendar: calendar).string(from: date)
    }
}
