import Foundation

/// Kaldırılmış bir uygulamadan kalan dosyalar (aynı bundle id altında toplanır).
struct LeftoverGroup: Identifiable, Sendable {
    let id: String
    let files: [FoundFile]
    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
}

/// `~/Library` altında, kurulu hiçbir uygulamaya ait olmayan bundle-id adlı öğeleri bulur.
///
/// Yanlış pozitifleri önlemek için temkinli davranır: aynı geliştiriciye (ör. `com.google`)
/// ait kurulu ya da çalışan bir uygulama varsa o geliştiricinin hiçbir kalıntısı listelenmez.
enum LeftoverScanner {
    /// Taranan klasörler ve isimlerinden atılacak uzantılar.
    private static let locations: [(path: String, suffix: String?)] = [
        ("Application Support", nil),
        ("Caches", nil),
        ("Preferences", ".plist"),
        ("Containers", nil),
        ("Saved Application State", ".savedState"),
        ("HTTPStorages", nil),
        ("HTTPStorages", ".binarycookies"),
        ("WebKit", nil),
        ("Logs", nil),
        ("Application Scripts", nil),
    ]

    /// `.app` paketi olmayan sistem/geliştirici araçları (Kısayollar, SwiftPM, Java, Android SDK…).
    private static let protectedVendors: Set<String> = [
        "com.apple", "is.workflow", "org.swift", "net.java", "com.android", "com.oracle",
    ]
    private static let appFolders = [
        "/Applications", "/System/Applications", "/System/Library/CoreServices",
        FileUtils.home.appending(path: "Applications").path(percentEncoded: false),
    ]

    static func scan(runningBundleIDs: Set<String>) -> [LeftoverGroup] {
        var knownVendors = Set((installedBundleIDs().union(runningBundleIDs)).map(vendor))
        knownVendors.formUnion(protectedVendors)
        if let own = Bundle.main.bundleIdentifier { knownVendors.insert(vendor(own)) }

        var groups: [String: [FoundFile]] = [:]
        let library = FileUtils.home.appending(path: "Library")
        for location in locations {
            let dir = library.appending(path: location.path)
            for url in FileUtils.contents(of: dir) ?? [] {
                var name = url.lastPathComponent
                if let suffix = location.suffix {
                    guard name.hasSuffix(suffix) else { continue }
                    name.removeLast(suffix.count)
                } else if name.hasSuffix(".binarycookies") {
                    continue // ayrı satırda, uzantısı atılarak işlenir
                }
                guard isBundleID(name), !name.hasSuffix(".cache"),
                      !knownVendors.contains(vendor(name)) else { continue }
                let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                groups[name, default: []].append(FoundFile(url: url, size: FileUtils.allocatedSize(of: url), date: date))
            }
        }
        return groups
            .map { LeftoverGroup(id: $0.key, files: $0.value) }
            .filter { $0.totalSize > 0 } // boş klasörler yer kazandırmaz, listeyi kalabalıklaştırır
            .sorted { $0.totalSize > $1.totalSize }
    }

    static func installedBundleIDs() -> Set<String> {
        var ids = Set<String>()
        for folder in appFolders {
            let enumerator = FileManager.default.enumerator(
                at: URL(filePath: folder),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            )
            while let url = enumerator?.nextObject() as? URL {
                if (enumerator?.level ?? 0) > 3 { enumerator?.skipDescendants() }
                guard url.pathExtension == "app" else { continue }
                if let id = Bundle(url: url)?.bundleIdentifier { ids.insert(id) }
            }
        }
        return ids
    }

    /// "com.vendor.app" → "com.vendor". Takım kimliği ("JQ525L2MZD.") ve "group." önekleri atılır:
    /// "JQ525L2MZD.group.com.adobe.x" → "com.adobe".
    private static func vendor(_ id: String) -> String {
        var parts = id.split(separator: ".").map(String.init)
        if let first = parts.first, first.count == 10,
           first.allSatisfy({ $0.isUppercase || $0.isNumber }) { parts.removeFirst() }
        if let first = parts.first, ["group", "groups", "systemgroup"].contains(first.lowercased()) { parts.removeFirst() }
        return parts.prefix(2).joined(separator: ".").lowercased()
    }

    private static func isBundleID(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9-]+\.[A-Za-z0-9-]+\.[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }
}
