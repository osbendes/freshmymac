import Foundation

/// Uygulamanın sunduğu tüm temizlik görevleri.
enum TaskCatalog {
    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static func lib(_ path: String) -> URL { home.appending(path: "Library/\(path)") }

    /// Tarayıcı önbellekleri `~/Library/Caches` altında; çift sayımı önlemek için
    /// kullanıcı önbelleği görevinden hariç tutulup ayrı görevde temizlenir.
    private static let browserCacheDirs = [
        "com.apple.Safari", "Google", "Firefox", "Mozilla",
        "com.microsoft.edgemac", "BraveSoftware", "company.thebrowser.Browser",
    ]

    static let dnsFlushID = "dns-flush"

    static let all: [CleanupTask] = [
        // MARK: Sistem
        CleanupTask(
            id: "user-caches",
            title: LText("Uygulama Önbellekleri", "App Caches"),
            short: LText("Uygulama Önbelleği", "App Cache"),
            subtitle: LText("~/Library/Caches altındaki geçici uygulama verileri", "Temporary app data in ~/Library/Caches"),
            icon: "archivebox",
            category: .system,
            action: .deleteContents(of: [lib("Caches")], excluding: browserCacheDirs + ["CloudKit", "com.apple.HomeKit", "FamilyCircle"])
        ),
        CleanupTask(
            id: "user-logs",
            title: LText("Kullanıcı Günlükleri", "User Logs"),
            short: LText("Günlükler", "Logs"),
            subtitle: LText("~/Library/Logs altındaki log ve çökme raporları", "Logs and crash reports in ~/Library/Logs"),
            icon: "doc.text",
            category: .system,
            action: .deleteContents(of: [lib("Logs")])
        ),
        CleanupTask(
            id: "trash",
            title: LText("Çöp Kutusu", "Trash"),
            subtitle: LText("Çöp Kutusu'nu kalıcı olarak boşaltır (Tam Disk Erişimi gerekebilir)", "Permanently empties the Trash (may need Full Disk Access)"),
            icon: "trash",
            category: .system,
            action: .deleteContents(of: [home.appending(path: ".Trash")]),
            selectedByDefault: false
        ),

        // MARK: Gizlilik
        CleanupTask(
            id: "browser-caches",
            title: LText("Tarayıcı Önbellekleri", "Browser Caches"),
            short: LText("Tarayıcı Önbelleği", "Browser Cache"),
            subtitle: LText("Safari, Chrome, Firefox, Edge, Brave, Arc önbellekleri", "Safari, Chrome, Firefox, Edge, Brave and Arc caches"),
            icon: "globe",
            category: .privacy,
            action: .deleteContents(of: browserCacheDirs.map { lib("Caches/\($0)") })
        ),
        CleanupTask(
            id: "browser-history",
            title: LText("Tarayıcı Geçmişi", "Browser History"),
            subtitle: LText("Safari, Chrome, Edge, Brave ziyaret geçmişi (tarayıcılar kapalı olmalı)", "Safari, Chrome, Edge and Brave history (browsers must be closed)"),
            icon: "clock.arrow.circlepath",
            category: .privacy,
            action: .deleteItems {
                browserFiles(
                    safari: ["Safari/History.db", "Safari/History.db-shm", "Safari/History.db-wal",
                             "Safari/LastSession.plist", "Safari/RecentlyClosedTabs.plist"],
                    chromium: ["History", "History-journal", "Visited Links", "Top Sites",
                               "Top Sites-journal", "Shortcuts", "Shortcuts-journal"]
                )
            },
            selectedByDefault: false,
            blockingApps: browserBundleIDs
        ),
        CleanupTask(
            id: "browser-cookies",
            title: LText("Tarayıcı Çerezleri", "Browser Cookies"),
            short: LText("Çerezler", "Cookies"),
            subtitle: LText("Tüm sitelerden oturumunuz kapanır (tarayıcılar kapalı olmalı)", "Signs you out of all websites (browsers must be closed)"),
            icon: "birthday.cake",
            category: .privacy,
            action: .deleteItems {
                browserFiles(
                    safari: ["Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies",
                             "Cookies/Cookies.binarycookies"],
                    chromium: ["Cookies", "Cookies-journal"]
                )
            },
            selectedByDefault: false,
            blockingApps: browserBundleIDs
        ),
        CleanupTask(
            id: dnsFlushID,
            title: LText("İnternet Önbelleğini Temizle (flushdns)", "Clear Internet Cache (flushdns)"),
            short: LText("İnternet Önbelleği", "Internet Cache"),
            subtitle: LText("DNS ve ARP önbelleğini sıfırlar; Windows'taki ipconfig /flushdns karşılığı", "Resets the DNS and ARP caches, like ipconfig /flushdns on Windows"),
            icon: "network",
            category: .privacy,
            action: .privileged([
                PrivilegedCommand(path: "/usr/bin/dscacheutil", arguments: ["-flushcache"]),
                PrivilegedCommand(path: "/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"]),
                PrivilegedCommand(path: "/usr/sbin/arp", arguments: ["-a", "-d"], ignoresFailure: true),
            ])
        ),
        CleanupTask(
            id: "quicklook",
            title: LText("Quick Look Küçük Resimleri", "Quick Look Thumbnails"),
            short: LText("Quick Look", "Quick Look"),
            subtitle: LText("Önizlenen dosyaların küçük resim önbelleğini sıfırlar", "Resets the thumbnail cache of previewed files"),
            icon: "eye",
            category: .privacy,
            action: .shell("qlmanage -r cache")
        ),

        // MARK: Performans
        CleanupTask(
            id: "purge-ram",
            title: LText("Belleği Boşalt", "Free Up Memory"),
            short: LText("Bellek (RAM)", "Memory (RAM)"),
            subtitle: LText("Etkin olmayan RAM'i serbest bırakır (purge)", "Releases inactive RAM (purge)"),
            icon: "memorychip",
            category: .performance,
            action: .privileged([PrivilegedCommand(path: "/usr/sbin/purge", arguments: [])]),
            selectedByDefault: false
        ),

        // MARK: Geliştirici
        CleanupTask(
            id: "xcode-derived",
            title: LText("Xcode DerivedData", "Xcode DerivedData"),
            subtitle: LText("Derleme ara dosyaları; Xcode gerektiğinde yeniden üretir", "Intermediate build files; Xcode regenerates them as needed"),
            icon: "hammer",
            category: .developer,
            action: .deleteContents(of: [lib("Developer/Xcode/DerivedData")]),
            isAvailable: { exists(lib("Developer/Xcode")) }
        ),
        CleanupTask(
            id: "simulators",
            title: LText("Kullanılamayan Simülatörler", "Unavailable Simulators"),
            short: LText("Simülatörler", "Simulators"),
            subtitle: LText("Artık desteklenmeyen iOS simülatörlerini siler", "Deletes iOS simulators that are no longer supported"),
            icon: "iphone",
            category: .developer,
            action: .shell("xcrun simctl delete unavailable"),
            isAvailable: { exists(URL(filePath: "/Applications/Xcode.app")) }
        ),
        CleanupTask(
            id: "homebrew",
            title: LText("Homebrew Temizliği", "Homebrew Cleanup"),
            short: LText("Homebrew", "Homebrew"),
            subtitle: LText("Eski paket sürümlerini ve indirme önbelleğini siler", "Removes old package versions and the download cache"),
            icon: "mug",
            category: .developer,
            action: .shell("brew cleanup -s --prune=all"),
            isAvailable: { Shell.which("brew") != nil }
        ),
        CleanupTask(
            id: "npm-cache",
            title: LText("npm Önbelleği", "npm Cache"),
            subtitle: LText("~/.npm/_cacache paket önbelleği", "Package cache in ~/.npm/_cacache"),
            icon: "shippingbox",
            category: .developer,
            action: .deleteContents(of: [home.appending(path: ".npm/_cacache")]),
            isAvailable: { exists(home.appending(path: ".npm/_cacache")) }
        ),
    ]

    private static func exists(_ url: URL) -> Bool { FileUtils.exists(url) }

    // MARK: Tarayıcı dosyaları

    /// Chromium tabanlı tarayıcıların `Application Support` altındaki kök klasörleri.
    private static let chromiumRoots = ["Google/Chrome", "Microsoft Edge", "BraveSoftware/Brave-Browser"]
    private static let browserBundleIDs = ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser"]

    /// `safari` yolları `~/Library`'ye, `chromium` yolları her profil klasörüne görelidir.
    private static func browserFiles(safari: [String], chromium: [String]) -> [URL] {
        var urls = safari.map { lib($0) }
        for root in chromiumRoots {
            let base = lib("Application Support/\(root)")
            let profiles = (FileUtils.contents(of: base) ?? []).filter {
                $0.lastPathComponent == "Default" || $0.lastPathComponent.hasPrefix("Profile ")
            }
            for profile in profiles {
                urls += chromium.map { profile.appending(path: $0) }
            }
        }
        return urls
    }
}
