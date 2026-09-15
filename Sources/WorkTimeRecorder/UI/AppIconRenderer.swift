import AppKit

/// 应用图标绘制：圆角方块渐变底 + 工时进度环 + 达标对勾。
///
/// 设计在 1024×1024 的坐标系中完成，再按目标尺寸等比渲染。
enum AppIconRenderer {
    static let designSize: CGFloat = 1024

    static func render(size: Int) -> Data? {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        representation.size = NSSize(width: size, height: size)
        guard let context = NSGraphicsContext(bitmapImageRep: representation) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let scale = CGFloat(size) / designSize
        context.cgContext.scaleBy(x: scale, y: scale)
        draw()
        NSGraphicsContext.restoreGraphicsState()

        return representation.representation(using: .png, properties: [:])
    }

    private static func draw() {
        let canvas = NSRect(x: 0, y: 0, width: designSize, height: designSize)
        // macOS 图标规范：内容区域约占画布 80%，四周留出透明边距。
        let tile = canvas.insetBy(dx: 100, dy: 100)
        let squircle = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

        // 投影
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 26
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        NSColor.black.setFill()
        squircle.fill()
        NSGraphicsContext.restoreGraphicsState()

        // 渐变底
        NSGraphicsContext.saveGraphicsState()
        squircle.addClip()
        NSGradient(colors: [Theme.accent, Theme.teal])?.draw(in: tile, angle: -45)

        // 左上角高光，让底色更有层次
        if let highlight = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.28),
            NSColor.white.withAlphaComponent(0)
        ]) {
            highlight.draw(
                fromCenter: NSPoint(x: tile.minX + tile.width * 0.25, y: tile.maxY - tile.height * 0.2),
                radius: 0,
                toCenter: NSPoint(x: tile.minX + tile.width * 0.25, y: tile.maxY - tile.height * 0.2),
                radius: tile.width * 0.85,
                options: []
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        // 工时进度环
        let center = NSPoint(x: tile.midX, y: tile.midY)
        let radius = tile.width * 0.30
        let ringWidth = tile.width * 0.075

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = ringWidth
        NSColor.white.withAlphaComponent(0.3).setStroke()
        track.stroke()

        let progress = NSBezierPath()
        progress.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - 360 * 0.75,
            clockwise: true
        )
        progress.lineWidth = ringWidth
        progress.lineCapStyle = .round
        NSColor.white.setStroke()
        progress.stroke()

        // 达标对勾
        let check = NSBezierPath()
        check.move(to: NSPoint(x: center.x - radius * 0.42, y: center.y + radius * 0.02))
        check.line(to: NSPoint(x: center.x - radius * 0.10, y: center.y - radius * 0.34))
        check.line(to: NSPoint(x: center.x + radius * 0.46, y: center.y + radius * 0.38))
        check.lineWidth = ringWidth * 0.82
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        NSColor.white.setStroke()
        check.stroke()
    }
}
