import ServiceManagement

/// "Open at login" via the modern SMAppService API (macOS 13+).
enum LoginItem {
    static func apply(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled { try service.register() }
            if !enabled, service.status == .enabled { try service.unregister() }
        } catch {
            // Not fatal: the user can add the app in System Settings → General → Login Items.
        }
    }
}
