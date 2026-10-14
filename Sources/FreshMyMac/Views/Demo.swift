import Foundation

/// README ve tanıtım görselleri için örnek içerik: `-demo YES` ile açılınca, ekran görüntüsü alınmadan
/// hemen önce gerçek tarama sonuçlarının yerine uydurma ama gerçekçi veriler konur. Gerçek dosya adları ve
/// kullanıcı adı görünmez. `-demoScene cleaned` Akıllı Temizlik'i temizlik bitmiş haliyle gösterir.
@MainActor
enum Demo {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "demo") }
    static var scene: String { UserDefaults.standard.string(forKey: "demoScene") ?? "" }

    private static let gb: Int64 = 1_000_000_000
    private static let mb: Int64 = 1_000_000

    /// Ölçülebilen görevlerin örnek boyutları.
    private static let taskSizes: [String: Int64] = [
        "user-caches": 4_200 * mb, "user-logs": 380 * mb, "trash": 1_100 * mb,
        "browser-caches": 2_300 * mb, "browser-history": 45 * mb, "browser-cookies": 12 * mb,
        "xcode-derived": 8_700 * mb, "npm-cache": 1_400 * mb,
    ]

    /// Ekran görüntülerinde seçili görünecek görevler.
    private static let selectedIDs: Set<String> = [
        "user-caches", "user-logs", "browser-caches", "quicklook", "xcode-derived", "simulators", "homebrew", "npm-cache",
    ]

    static func apply(to state: AppState) {
        state.disk = DiskInfo(total: 494 * gb, available: 82 * gb)

        let cleaner = state.cleaner
        for task in cleaner.tasks {
            cleaner.scanStates[task.id] = task.isMeasurable ? .measured(bytes: taskSizes[task.id] ?? 0, items: 1) : .notMeasurable
        }
        cleaner.selection = selectedIDs.intersection(cleaner.tasks.map(\.id))
        cleaner.log = []
        cleaner.lastFreedBytes = nil
        if scene == "cleaned" {
            let freed: Int64 = 15_080 * mb
            cleaner.lastFreedBytes = freed
            cleaner.log = [
                .init(title: L("Uygulama Önbellekleri", "App Caches"), detail: L("1.284 öğe kaldırıldı, 4,2 GB boşaltıldı.", "1,284 items removed, 4.2 GB freed."), success: true),
                .init(title: "Xcode DerivedData", detail: L("37 öğe kaldırıldı, 8,7 GB boşaltıldı.", "37 items removed, 8.7 GB freed."), success: true),
                .init(title: L("Tarayıcı Önbellekleri", "Browser Caches"), detail: L("612 öğe kaldırıldı, 2,3 GB boşaltıldı.", "612 items removed, 2.3 GB freed."), success: true),
            ]
            for id in ["user-caches", "xcode-derived", "browser-caches"] { cleaner.scanStates[id] = .measured(bytes: 0, items: 0) }
        }

        let home = FileUtils.home
        func file(_ path: String, _ size: Int64, daysAgo: Double) -> FoundFile {
            FoundFile(url: home.appending(path: path), size: size, date: Date(timeIntervalSinceNow: -daysAgo * 86_400))
        }
        let large = state.largeFiles
        large.results = [
            file("Movies/Recordings/Keynote-Rehearsal-2024.mov", 4_800 * mb, daysAgo: 410),
            file("Movies/Family/Summer-Trip-4K.mp4", 3_100 * mb, daysAgo: 220),
            file("Downloads/Xcode_15.4.xip", 7_600 * mb, daysAgo: 160),
            file("Downloads/Ubuntu-22.04-desktop-arm64.iso", 1_900 * mb, daysAgo: 300),
            file("Documents/Archive/Client-Backup-2023.zip", 2_100 * mb, daysAgo: 520),
            file("Downloads/Figma-Installer.dmg", 410 * mb, daysAgo: 95),
            file("Desktop/Brand-Identity-Master.psd", 1_400 * mb, daysAgo: 340),
        ]
        large.hasScanned = true
        large.status = nil
        large.selection = Set(large.results.prefix(5).map(\.url))

        func leftover(_ app: String, _ items: [(String, Int64)]) -> LeftoverGroup {
            LeftoverGroup(id: app, files: items.map { FoundFile(url: home.appending(path: $0.0), size: $0.1, date: nil) })
        }
        let leftovers = state.leftovers
        leftovers.groups = [
            leftover("us.zoom.xos", [("Library/Application Support/zoom.us", 640 * mb), ("Library/Caches/us.zoom.xos", 190 * mb),
                                     ("Library/Preferences/us.zoom.xos.plist", 120_000)]),
            leftover("com.adobe.acc.AdobeCreativeCloud", [("Library/Application Support/Adobe/OOBE", 1_700 * mb),
                                                         ("Library/Caches/com.adobe.acc.AdobeCreativeCloud", 410 * mb)]),
            leftover("com.spotify.client", [("Library/Caches/com.spotify.client", 290 * mb),
                                            ("Library/Application Support/Spotify", 22 * mb)]),
            leftover("com.tinyspeck.slackmacgap", [("Library/Containers/com.tinyspeck.slackmacgap", 180 * mb)]),
        ]
        leftovers.hasScanned = true
        leftovers.status = nil
        leftovers.selection = ["us.zoom.xos", "com.spotify.client"]

        func agent(_ scope: LaunchItem.Scope, _ label: String, program: String? = nil, loaded: Bool? = true) -> LaunchItem {
            let dir = scope == .userAgent ? "/Users/demo/Library/LaunchAgents" : scope.directory.path(percentEncoded: false)
            return LaunchItem(plist: URL(filePath: "\(dir)/\(label).plist"), label: label, program: program, scope: scope, isLoaded: loaded)
        }
        let launch = state.launchItems
        launch.items = [
            agent(.userAgent, "com.spotify.webhelper"),
            agent(.userAgent, "com.dropbox.DropboxMacUpdate.agent", loaded: false),
            agent(.userAgent, "com.oldvpn.helper", program: "/Applications/OldVPN.app/Contents/MacOS/vpn-helper", loaded: false),
            agent(.globalAgent, "com.adobe.ccxprocess"),
            agent(.globalAgent, "us.zoom.updater.login.check", loaded: false),
            agent(.daemon, "com.docker.vmnetd", loaded: nil),
            agent(.daemon, "com.microsoft.autoupdate.helper", loaded: nil),
        ]
        launch.status = nil
        launch.selection = []
    }
}
