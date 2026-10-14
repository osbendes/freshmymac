import Foundation

/// Tarama ve temizleme işlemlerini yürütür. Ana iş parçacığından bağımsız çalışır.
enum CleanupEngine {
    // MARK: Tarama

    static func scan(_ task: CleanupTask) -> ScanState {
        switch task.action {
        case let .deleteContents(dirs, excluding, olderThanDays):
            var bytes: Int64 = 0
            var items = 0
            var anyReadable = false
            for dir in dirs {
                guard let children = FileUtils.contents(of: dir) else { continue }
                anyReadable = true
                for child in filtered(children, excluding: excluding, olderThanDays: olderThanDays) {
                    bytes += FileUtils.allocatedSize(of: child)
                    items += 1
                }
            }
            if dirs.contains(where: FileUtils.exists) && !anyReadable { return .noAccess }
            return .measured(bytes: bytes, items: items)

        case let .deleteItems(resolve):
            let urls = resolve()
            // Korumalı klasörlerdeki (ör. ~/Library/Safari) dosyalar izin yokken "yok" görünür;
            // üst klasörün okunabilirliğine bakarak bunu ayırt ediyoruz.
            let parents = Set(urls.map { $0.deletingLastPathComponent() })
            if parents.contains(where: { FileUtils.exists($0) && FileUtils.contents(of: $0) == nil }) {
                return .noAccess
            }
            let existing = urls.filter(FileUtils.exists)
            return .measured(bytes: existing.reduce(0) { $0 + FileUtils.allocatedSize(of: $1) }, items: existing.count)

        case .shell, .privileged:
            return .notMeasurable
        }
    }

    // MARK: Temizleme

    static func clean(_ task: CleanupTask) async -> CleanupResult {
        switch task.action {
        case let .deleteContents(dirs, excluding, olderThanDays):
            let urls = dirs.flatMap { dir in
                filtered(FileUtils.contents(of: dir) ?? [], excluding: excluding, olderThanDays: olderThanDays)
            }
            return delete(urls)
        case let .deleteItems(resolve):
            return delete(resolve().filter(FileUtils.exists))
        case let .shell(command):
            return result(from: await Shell.run(command))
        case let .privileged(commands):
            return await PrivilegedAccess.run(commands)
        }
    }

    /// Yetkili görevleri birlikte çalıştırır: izin yoksa şifre yalnızca bir kez sorulur.
    static func cleanPrivileged(_ tasks: [CleanupTask]) async -> CleanupResult {
        await PrivilegedAccess.run(tasks.flatMap { task -> [PrivilegedCommand] in
            if case let .privileged(commands) = task.action { return commands }
            return []
        })
    }

    // MARK: Yardımcılar

    private static func delete(_ urls: [URL]) -> CleanupResult {
        var result = CleanupResult()
        for url in urls {
            let size = FileUtils.allocatedSize(of: url)
            do {
                try FileManager.default.removeItem(at: url)
                result.freedBytes += size
                result.removedItems += 1
            } catch {
                result.failedItems += 1
            }
        }
        if result.failedItems > 0 {
            result.message = L("\(result.failedItems) öğe kullanımda veya korumalı olduğu için atlandı.", "\(result.failedItems) items were skipped because they are in use or protected.")
        }
        return result
    }

    static func result(from output: Shell.Output) -> CleanupResult {
        var result = CleanupResult()
        result.succeeded = output.status == 0
        let trimmed = output.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !result.succeeded {
            result.message = trimmed.contains("-128") ? L("Kullanıcı tarafından iptal edildi.", "Cancelled by user.") : trimmed
        } else if !trimmed.isEmpty {
            result.message = trimmed.split(separator: "\n").last.map(String.init)
        }
        return result
    }

    private static func filtered(_ urls: [URL], excluding: [String], olderThanDays: Int?) -> [URL] {
        let cutoff = olderThanDays.map { Date.now.addingTimeInterval(-Double($0) * 86_400) }
        let ownBundle = Bundle.main.bundleIdentifier
        return urls.filter { url in
            let name = url.lastPathComponent
            if excluding.contains(name) || name == ownBundle || name == ".DS_Store" { return false }
            if let cutoff,
               let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               modified > cutoff {
                return false
            }
            return true
        }
    }
}
