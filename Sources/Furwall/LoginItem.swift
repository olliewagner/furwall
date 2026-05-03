import Foundation
import ServiceManagement

/// Open-at-login toggle. Uses SMAppService.mainApp on macOS 13+ — no helper
/// bundle required, no LaunchAgent plist.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns the post-toggle state (true = enabled). On error, returns the
    /// previous state — the menu observes this to keep its toggle honest.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return isEnabled
        } catch {
            NSLog("Furwall: SMAppService toggle failed — \(error)")
            return isEnabled
        }
    }
}
