import AppKit
import CoreGraphics
import Foundation

/// 监听锁屏、解锁与休眠唤醒事件。
///
/// 系统通知（`com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`）是主通道，
/// 另外用 `CGSessionCopyCurrentDictionary` 轮询兜底，避免个别系统版本不发通知。
final class ScreenLockMonitor {
    var onLock: (() -> Void)?
    var onUnlock: (() -> Void)?

    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var lastKnownLocked: Bool?

    func start() {
        guard distributedObservers.isEmpty else { return }

        let distributed = DistributedNotificationCenter.default()
        distributedObservers.append(
            distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                self?.apply(locked: true)
            }
        )
        distributedObservers.append(
            distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
                self?.apply(locked: false)
            }
        )

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.apply(locked: true)
            }
        )
        workspaceObservers.append(
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                // 唤醒后不一定解锁（可能停在锁屏界面），以会话状态为准。
                self?.refreshFromSession(publish: true)
            }
        )

        refreshFromSession(publish: false)
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshFromSession(publish: true)
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        let distributed = DistributedNotificationCenter.default()
        distributedObservers.forEach { distributed.removeObserver($0) }
        distributedObservers.removeAll()
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspace.removeObserver($0) }
        workspaceObservers.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    deinit {
        pollTimer?.invalidate()
    }

    /// 当前是否处于锁屏状态；无法判断时返回 nil。
    private func currentLockState() -> Bool? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return nil }
        if let locked = session["CGSSessionScreenIsLocked"] as? Bool {
            return locked
        }
        return false
    }

    private func refreshFromSession(publish: Bool) {
        guard let locked = currentLockState() else { return }
        if publish {
            apply(locked: locked)
        } else {
            lastKnownLocked = locked
        }
    }

    private func apply(locked: Bool) {
        guard lastKnownLocked != locked else { return }
        lastKnownLocked = locked
        if locked {
            onLock?()
        } else {
            onUnlock?()
        }
    }
}
