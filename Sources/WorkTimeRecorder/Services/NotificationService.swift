import AppKit
import Foundation
import UserNotifications

/// 系统通知封装。
///
/// 只有以 .app 包形式运行时才注册通知，避免 `swift run` 直接执行二进制时
/// 因缺少 bundle identifier 而触发系统异常。
final class NotificationService {
    static let shared = NotificationService()

    /// 注意：未打包运行时获取当前通知中心会直接崩溃（bundleProxyForCurrentProcess is nil），
    /// 所以访问必须懒加载，并且只在该类确认可用的打包环境下使用。
    private lazy var center: UNUserNotificationCenter = UNUserNotificationCenter.current()
    private var didRequestAuthorization = false

    private var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    func requestAuthorizationIfNeeded() {
        guard isSupported, !didRequestAuthorization else { return }
        didRequestAuthorization = true
        center.getNotificationSettings { [center] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func notify(title: String, body: String, identifier: String = UUID().uuidString) {
        guard isSupported else {
            NSLog("[WorkTimeRecorder] 通知（未打包运行，仅记录）：%@ - %@", title, body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request)
    }

    func authorizationStatusDescription() async -> String {
        guard isSupported else { return "未打包运行，系统通知不可用" }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "已授权"
        case .denied: return "已被系统拒绝"
        case .notDetermined: return "等待授权"
        @unknown default: return "未知状态"
        }
    }

    func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }
}
