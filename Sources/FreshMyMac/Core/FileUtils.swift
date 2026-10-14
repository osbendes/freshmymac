import Foundation

/// Tarama sonuçlarında listelenen tek bir dosya/klasör.
struct FoundFile: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let size: Int64
    let date: Date?

    var name: String { url.lastPathComponent }
}

enum FileUtils {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Klasör okunamıyorsa `nil` döner (izin yok ya da yok).
    static func contents(of dir: URL, keys: [URLResourceKey] = [.contentModificationDateKey]) -> [URL]? {
        try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [])
    }

    /// Dosyanın ya da klasörün diskte kapladığı toplam alan.
    static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else { return Int64(values.totalFileAllocatedSize ?? 0) }

        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        )
        while let file = enumerator?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Öğeleri Çöp Kutusu'na taşır; geri alınabilir.
    static func moveToTrash(_ urls: [URL]) -> CleanupResult {
        var result = CleanupResult()
        for url in urls {
            let size = allocatedSize(of: url)
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                result.freedBytes += size
                result.removedItems += 1
            } catch {
                result.failedItems += 1
            }
        }
        if result.failedItems > 0 {
            result.message = L("\(result.failedItems) öğe taşınamadı (izin veya kullanımda).", "\(result.failedItems) items could not be moved (permission or in use).")
        }
        return result
    }
}

enum Format {
    static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file).locale(L10n.locale))
    }

    static func date(_ value: Date?) -> String {
        value?.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.locale)) ?? "—"
    }

    static func dateTime(_ value: Date?) -> String {
        value?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(L10n.locale)) ?? "—"
    }
}
