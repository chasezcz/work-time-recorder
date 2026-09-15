import AppKit

/// 状态栏图标：外圈是今日工时进度环，中心圆点表示是否在上班状态，
/// 达标后中心变成对勾。使用模板图，自动适配浅色/深色菜单栏。
enum MenuBarIcon {
    static func make(progress: Double, isWorking: Bool, hasRecord: Bool, size: CGFloat = 18) -> NSImage {
        let clamped = max(0, min(1, progress))
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let lineWidth = max(1.1, size * 0.085)
            let inset = lineWidth / 2 + size * 0.08
            let ringRect = rect.insetBy(dx: inset, dy: inset)
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = ringRect.width / 2

            // 进度环底
            let track = NSBezierPath(ovalIn: ringRect)
            track.lineWidth = lineWidth
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()

            // 今日进度
            if hasRecord, clamped > 0.001 {
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: 90,
                    endAngle: 90 - 360 * clamped,
                    clockwise: true
                )
                arc.lineWidth = lineWidth * 1.15
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }

            if clamped >= 0.999 {
                // 达标：中心画对勾
                let check = NSBezierPath()
                check.move(to: NSPoint(x: center.x - size * 0.17, y: center.y + size * 0.01))
                check.line(to: NSPoint(x: center.x - size * 0.04, y: center.y - size * 0.13))
                check.line(to: NSPoint(x: center.x + size * 0.18, y: center.y + size * 0.15))
                check.lineWidth = max(1.2, size * 0.11)
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                NSColor.black.setStroke()
                check.stroke()
            } else {
                let dotRadius = size * 0.12
                let dotRect = NSRect(
                    x: center.x - dotRadius,
                    y: center.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                let dot = NSBezierPath(ovalIn: dotRect)
                dot.lineWidth = max(1, lineWidth * 0.7)
                if isWorking {
                    NSColor.black.setFill()
                    dot.fill()
                } else {
                    NSColor.black.setStroke()
                    dot.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
