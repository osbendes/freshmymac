import AppKit
import ServiceManagement
import UserNotifications

struct DiskInfo: Sendable {
    let total: Int64
    let available: Int64
    var used: Int64 { total - available }

    static func current() -> DiskInfo? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(filePath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return DiskInfo(total: Int64(total), available: available)
    }
}

enum AppEnvironment {
    /// `swift run` ile çalışırken .app paketi yoktur; bildirim ve oturum açılışı gibi
    /// paket gerektiren özellikler devre dışı kalır.
    static var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }
}

enum LoginItem {
    static var isEnabled: Bool {
        AppEnvironment.isBundled && SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

enum Notifier {
    static func requestAuthorization() async {
        guard AppEnvironment.isBundled else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func post(title: String, body: String) async {
        guard AppEnvironment.isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

enum SystemSettings {
    static func openLoginItems() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
