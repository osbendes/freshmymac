import Foundation

/// Oturum açılışında / arka planda çalışan bir launchd öğesi.
struct LaunchItem: Identifiable, Sendable {
    enum Scope: String, CaseIterable, Sendable {
        case userAgent, globalAgent, daemon

        var title: String {
            switch self {
            case .userAgent: L("Kullanıcı Ajanları", "User Agents")
            case .globalAgent: L("Genel Ajanlar", "Global Agents")
            case .daemon: L("Sistem Servisleri", "System Daemons")
            }
        }

        var directory: URL {
            switch self {
            case .userAgent: FileUtils.home.appending(path: "Library/LaunchAgents")
            case .globalAgent: URL(filePath: "/Library/LaunchAgents")
            case .daemon: URL(filePath: "/Library/LaunchDaemons")
            }
        }

        var requiresAdmin: Bool { self != .userAgent }
    }

    var id: URL { plist }
    let plist: URL
    let label: String
    let program: String?
    let scope: Scope
    /// Kullanıcı oturumunda yüklü mü? Sistem servisleri için bilinemez (`nil`).
    let isLoaded: Bool?

    /// Çalıştıracağı program artık yoksa öğe büyük ihtimalle kaldırılmış bir uygulamadan kalmıştır.
    var isOrphaned: Bool {
        guard let program, program.hasPrefix("/") else { return false }
        return !FileManager.default.fileExists(atPath: program)
    }
}

enum LaunchItemScanner {
    static func scan() async -> [LaunchItem] {
        let loaded = await loadedLabels()
        var items: [LaunchItem] = []
        for scope in LaunchItem.Scope.allCases {
            for url in FileUtils.contents(of: scope.directory) ?? [] where url.pathExtension == "plist" {
                let dict = NSDictionary(contentsOf: url) as? [String: Any] ?? [:]
                let label = dict["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                let program = dict["Program"] as? String ?? (dict["ProgramArguments"] as? [String])?.first
                items.append(LaunchItem(
                    plist: url,
                    label: label,
                    program: program,
                    scope: scope,
                    isLoaded: scope == .daemon ? nil : loaded.contains(label)
                ))
            }
        }
        return items.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Öğeleri durdurur ve plist dosyalarını Çöp Kutusu'na taşır.
    /// Yönetici gerektirenler tek bir şifre isteminde birlikte işlenir.
    static func remove(_ items: [LaunchItem]) async -> CleanupResult {
        let trash = Shell.quote(FileUtils.home.appending(path: ".Trash/").path(percentEncoded: false))
        var result = CleanupResult()
        var adminCommands: [String] = []

        for item in items {
            let plist = Shell.quote(item.plist.path(percentEncoded: false))
            switch item.scope {
            case .userAgent:
                _ = await Shell.run("launchctl bootout gui/\(getuid()) \(plist)")
                let moved = FileUtils.moveToTrash([item.plist])
                result.removedItems += moved.removedItems
                result.failedItems += moved.failedItems
            case .globalAgent:
                _ = await Shell.run("launchctl bootout gui/\(getuid()) \(plist)")
                adminCommands.append("mv \(plist) \(trash)")
            case .daemon:
                adminCommands.append("launchctl bootout system \(plist) 2>/dev/null; mv \(plist) \(trash)")
            }
        }

        if !adminCommands.isEmpty {
            let admin = CleanupEngine.result(from: await Shell.runAsAdmin(adminCommands.joined(separator: "; ")))
            if admin.succeeded {
                result.removedItems += adminCommands.count
            } else {
                result.failedItems += adminCommands.count
                result.succeeded = false
                result.message = admin.message
            }
        }
        return result
    }

    private static func loadedLabels() async -> Set<String> {
        let output = await Shell.run("launchctl list").output
        let labels = output.split(separator: "\n").dropFirst().compactMap { line in
            line.split(separator: "\t").last.map(String.init)
        }
        return Set(labels)
    }
}
