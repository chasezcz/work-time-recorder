import AppKit
import WorkTimeCore

/// 圆环进度指示器（渐变色描边）。
final class ProgressRingView: NSView {
    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }

    var lineWidth: CGFloat = 11 {
        didSet { needsDisplay = true }
    }

    var colors: [NSColor] = Theme.progressColors {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let radius = min(bounds.width, bounds.height) / 2 - lineWidth / 2
        guard radius > 0 else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        context.setLineWidth(lineWidth)
        context.setStrokeColor(Theme.chartTrack.cgColor)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()

        let clamped = max(0, min(1, progress))
        guard clamped > 0.0005 else { return }

        let arc = CGMutablePath()
        arc.addArc(
            center: center,
            radius: radius,
            startAngle: .pi / 2,
            endAngle: .pi / 2 - CGFloat(clamped) * 2 * .pi,
            clockwise: true
        )
        let strokePath = arc.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)

        context.saveGState()
        context.addPath(strokePath)
        context.clip()
        NSGradient(colors: colors)?.draw(in: bounds, angle: -45)
        context.restoreGState()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// 图表中的一根柱子。
struct BarChartDatum {
    var title: String
    var regularHours: Double
    var overtimeHours: Double
    var targetHours: Double
    var isCurrent: Bool
    var isOffDay: Bool

    var totalHours: Double { regularHours + overtimeHours }
}

/// 手绘柱状图：达标部分用主题渐变，加班部分用橙色堆叠，虚线表示目标。
final class BarChartView: NSView {
    var data: [BarChartDatum] = [] {
        didSet { needsDisplay = true }
    }

    var emptyText = "当前周期暂无数据"

    override func draw(_ dirtyRect: NSRect) {
        let axisWidth: CGFloat = 34
        let labelHeight: CGFloat = 20
        let plot = NSRect(
            x: axisWidth,
            y: labelHeight,
            width: max(0, bounds.width - axisWidth - 10),
            height: max(0, bounds.height - labelHeight - 12)
        )
        guard plot.width > 10, plot.height > 10 else { return }

        let maxValue = chartMaxValue()
        drawGrid(plot: plot, maxValue: maxValue)

        guard !data.isEmpty else {
            drawCentered(emptyText, in: plot, color: .tertiaryLabelColor, font: Fonts.system(12))
            return
        }

        let slot = plot.width / CGFloat(data.count)
        let barWidth = min(30, max(4, slot * 0.58))

        for (index, datum) in data.enumerated() {
            let originX = plot.minX + slot * CGFloat(index) + (slot - barWidth) / 2

            let regularHeight = plot.height * CGFloat(datum.regularHours / maxValue)
            if regularHeight > 0.5 {
                let rect = NSRect(x: originX, y: plot.minY, width: barWidth, height: regularHeight)
                let path = NSBezierPath(roundedRect: rect, xRadius: min(4, barWidth / 2), yRadius: min(4, barWidth / 2))
                let colors = datum.isCurrent ? Theme.progressColors : [Theme.accentSoft, Theme.accentSoft]
                fill(path, colors: colors)
            }

            let overtimeHeight = plot.height * CGFloat(datum.overtimeHours / maxValue)
            if overtimeHeight > 0.5 {
                let rect = NSRect(x: originX, y: plot.minY + regularHeight, width: barWidth, height: overtimeHeight)
                let path = NSBezierPath(roundedRect: rect, xRadius: min(4, barWidth / 2), yRadius: min(4, barWidth / 2))
                fill(path, colors: Theme.overtimeColors)
            }

            if datum.targetHours > 0 {
                let y = plot.minY + plot.height * CGFloat(datum.targetHours / maxValue)
                let marker = NSBezierPath()
                marker.move(to: NSPoint(x: originX - 2, y: y))
                marker.line(to: NSPoint(x: originX + barWidth + 2, y: y))
                marker.lineWidth = 1.4
                marker.setLineDash([3, 2], count: 2, phase: 0)
                Theme.warning.setStroke()
                marker.stroke()
            }

            drawCentered(
                datum.title,
                in: NSRect(x: plot.minX + slot * CGFloat(index), y: 0, width: slot, height: labelHeight - 4),
                color: .secondaryLabelColor,
                font: Fonts.system(10)
            )
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private func chartMaxValue() -> Double {
        let values = data.map { max($0.totalHours, $0.targetHours) }
        let peak = max(values.max() ?? 8, 4)
        return (peak / 4).rounded(.up) * 4
    }

    private func drawGrid(plot: NSRect, maxValue: Double) {
        let steps = 4
        for step in 0...steps {
            let ratio = CGFloat(step) / CGFloat(steps)
            let y = plot.minY + plot.height * ratio
            let line = NSBezierPath()
            line.move(to: NSPoint(x: plot.minX, y: y))
            line.line(to: NSPoint(x: plot.maxX, y: y))
            line.lineWidth = 1
            Theme.gridLine.setStroke()
            line.stroke()

            let hours = maxValue * Double(step) / Double(steps)
            let text = String(format: "%.0fh", hours)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Fonts.system(9),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                at: NSPoint(x: plot.minX - size.width - 6, y: y - size.height / 2),
                withAttributes: attributes
            )
        }
    }

    private func fill(_ path: NSBezierPath, colors: [NSColor]) {
        guard let gradient = NSGradient(colors: colors) else { return }
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        gradient.draw(in: path.bounds, angle: 90)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawCentered(_ text: String, in rect: NSRect, color: NSColor, font: NSFont) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}

/// 一天 0–24 点的时间轴，标出每一段上班时间。
final class DayTimelineView: NSView {
    var interval: DateInterval = DateInterval(start: Date(), duration: 86400) {
        didSet { needsDisplay = true }
    }

    var segments: [(start: Date, end: Date)] = [] {
        didSet { needsDisplay = true }
    }

    var calendar: Calendar = AppCalendar.calendar() {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let labelHeight: CGFloat = 16
        let barHeight: CGFloat = max(12, bounds.height - labelHeight - 6)
        let barRect = NSRect(x: 0, y: labelHeight + 4, width: bounds.width, height: barHeight)
        let total = max(1, interval.end.timeIntervalSince(interval.start))

        Theme.chartTrack.setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 6, yRadius: 6).fill()

        // 每 6 小时一条分隔线
        for step in 1..<4 {
            let x = barRect.minX + barRect.width * CGFloat(step) / 4
            let gridLine = NSBezierPath()
            gridLine.move(to: NSPoint(x: x, y: barRect.minY))
            gridLine.line(to: NSPoint(x: x, y: barRect.maxY))
            gridLine.lineWidth = 1
            Theme.gridLine.setStroke()
            gridLine.stroke()
        }

        for segment in segments {
            let startRatio = max(0, min(1, segment.start.timeIntervalSince(interval.start) / total))
            let endRatio = max(0, min(1, segment.end.timeIntervalSince(interval.start) / total))
            guard endRatio > startRatio else { continue }
            let rect = NSRect(
                x: barRect.minX + barRect.width * CGFloat(startRatio),
                y: barRect.minY,
                width: max(3, barRect.width * CGFloat(endRatio - startRatio)),
                height: barRect.height
            )
            let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
            guard let gradient = NSGradient(colors: Theme.progressColors) else { continue }
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            gradient.draw(in: path.bounds, angle: 0)
            NSGraphicsContext.restoreGraphicsState()
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Fonts.system(9),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        for step in 0...4 {
            let ratio = CGFloat(step) / 4
            let tick = interval.start.addingTimeInterval(total * Double(ratio))
            let text = labelText(for: tick)
            let size = (text as NSString).size(withAttributes: attributes)
            var x = bounds.width * ratio - size.width / 2
            x = min(max(0, x), bounds.width - size.width)
            (text as NSString).draw(at: NSPoint(x: x, y: 0), withAttributes: attributes)
        }
    }

    /// 窗口起点当天显示 `04:00`，跨过午夜后显示 `次日04:00`。
    private func labelText(for date: Date) -> String {
        let text = AppCalendar.formatter("HH:mm", calendar: calendar).string(from: date)
        return calendar.isDate(date, inSameDayAs: interval.start) ? text : "次日\(text)"
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
