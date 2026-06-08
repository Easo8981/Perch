import AppKit
import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp` for the "Launch at Login" toggle.
///
/// Login-item registration only works when Perch is running as a real, signed `.app`
/// bundle (see `Scripts/build-app.sh`). When launched unbundled via `swift run`, there's
/// no bundle identifier, so `isAvailable` is false and the menu item is hidden.
@MainActor
final class LoginItemController {
    /// Whether launch-at-login can be controlled (i.e. we're a bundled app).
    var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    /// Whether Perch is currently registered to launch at login.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Perch login-item \(enabled ? "register" : "unregister") failed: \(error)")
            return false
        }
    }

    func toggle() {
        setEnabled(!isEnabled)
    }
}
