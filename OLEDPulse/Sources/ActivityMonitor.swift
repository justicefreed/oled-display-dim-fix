import AppKit
import IOKit.pwr_mgt

/// Tracks the system states during which pulsing should be skipped.
final class ActivityMonitor {
    private(set) var screenLocked = false
    private(set) var screensaverRunning = false
    private(set) var screensAsleep = false
    private(set) var systemAsleep = false

    init() {
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            screenLocked = session["CGSSessionScreenIsLocked"] as? Bool ?? false
        }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, "com.apple.screenIsLocked") { $0.screenLocked = true }
        observe(distributed, "com.apple.screenIsUnlocked") { $0.screenLocked = false }
        observe(distributed, "com.apple.screensaver.didstart") { $0.screensaverRunning = true }
        observe(distributed, "com.apple.screensaver.didstop") { $0.screensaverRunning = false }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification.rawValue) { $0.screensAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification.rawValue) { $0.screensAsleep = false }
        observe(workspace, NSWorkspace.willSleepNotification.rawValue) { $0.systemAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification.rawValue) { $0.systemAsleep = false }
    }

    var pauseReason: String? {
        if systemAsleep { return "system asleep" }
        if screensAsleep { return "displays asleep" }
        if screenLocked { return "screen locked" }
        if screensaverRunning { return "screensaver running" }
        return nil
    }

    /// Heuristic: some app holds a display-sleep assertion (as video players do) and has a window
    /// covering the whole display (as full-screen windows do).
    func isPlayingFullScreenVideo(on display: CGDirectDisplayID) -> Bool {
        guard anyDisplaySleepAssertion() else { return false }
        let bounds = CGDisplayBounds(display)
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return windows.contains { window in
            guard window[kCGWindowLayer as String] as? Int == 0,
                  window[kCGWindowOwnerPID as String] as? pid_t != ownPID,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict) else { return false }
            return frame.insetBy(dx: -1, dy: -1).contains(bounds)
        }
    }

    private func anyDisplaySleepAssertion() -> Bool {
        var assertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&assertions) == kIOReturnSuccess,
              let byProcess = assertions?.takeRetainedValue() as NSDictionary? else { return false }
        let displayTypes: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]
        return byProcess.allValues.contains { list in
            (list as? [[String: Any]] ?? []).contains { displayTypes.contains($0["AssertType"] as? String ?? "") }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: String, _ update: @escaping (ActivityMonitor) -> Void) {
        center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            if let self { update(self) }
        }
    }
}
