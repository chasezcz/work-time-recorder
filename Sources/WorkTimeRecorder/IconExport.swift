import AppKit

/// `--render-icons <目录>`：生成 AppIcon.iconset 与预览图，供打包脚本使用。
enum IconExport {
    static func run(directory: String) -> Int32 {
        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        guard let master = AppIconRenderer.render(size: 1024) else {
            FileHandle.standardError.write(Data("图标渲染失败\n".utf8))
            return 1
        }
        write(master, to: directoryURL.appendingPathComponent("icon-preview-1024.png"))

        let iconset = directoryURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

        let variants: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024)
        ]
        for (name, size) in variants {
            guard let data = AppIconRenderer.render(size: size) else { continue }
            write(data, to: iconset.appendingPathComponent("\(name).png"))
        }

        if let preview = renderMenuBarPreview() {
            write(preview, to: directoryURL.appendingPathComponent("menubar-preview.png"))
        }

        print("图标已生成：\(directoryURL.path)")
        return 0
    }

    /// 状态栏图标在浅色/深色菜单栏下的效果预览。
    private static func renderMenuBarPreview() -> Data? {
        let width = 260
        let height = 120
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        representation.size = NSSize(width: width, height: height)
        guard let context = NSGraphicsContext(bitmapImageRep: representation) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        let lightRect = NSRect(x: 0, y: 0, width: CGFloat(width) / 2, height: CGFloat(height))
        let darkRect = NSRect(x: CGFloat(width) / 2, y: 0, width: CGFloat(width) / 2, height: CGFloat(height))
        NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1).setFill()
        lightRect.fill()
        NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1).setFill()
        darkRect.fill()

        // 三种状态：未达标进行中、已达标、未打卡
        let states: [(progress: Double, isWorking: Bool, hasRecord: Bool)] = [
            (0.35, true, true),
            (1.0, false, true),
            (0.0, false, false)
        ]
        for (index, state) in states.enumerated() {
            let icon = MenuBarIcon.make(
                progress: state.progress,
                isWorking: state.isWorking,
                hasRecord: state.hasRecord,
                size: 22
            )
            let x = 20 + CGFloat(index) * 74
            let frame = NSRect(x: x, y: (CGFloat(height) - 22) / 2, width: 22, height: 22)
            icon.draw(in: frame)

            // 深色菜单栏下的效果：模板图按白色重新着色。
            let darkFrame = frame.offsetBy(dx: CGFloat(width) / 2, dy: 0)
            icon.draw(in: darkFrame)
            NSGraphicsContext.saveGraphicsState()
            NSColor.white.setFill()
            darkFrame.fill(using: .sourceAtop)
            NSGraphicsContext.restoreGraphicsState()
        }

        NSGraphicsContext.restoreGraphicsState()
        return representation.representation(using: .png, properties: [:])
    }

    private static func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("写入失败 \(url.lastPathComponent): \(error)\n".utf8))
        }
    }
}
