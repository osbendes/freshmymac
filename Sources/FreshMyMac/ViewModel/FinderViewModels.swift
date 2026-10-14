import AppKit
import Observation

// MARK: - Büyük ve eski dosyalar

@MainActor
@Observable
final class LargeFilesViewModel {
    var scopes: Set<LargeFileScope> = [.downloads, .desktop, .documents, .movies]
    var mode: LargeFileMode = .large
    var minSizeMB = 100
    var olderThanDays = 30

    var results: [FoundFile] = [] {
        didSet { grouped = Dictionary(grouping: results) { FileKind(url: $0.url) } }
    }
    private(set) var grouped: [FileKind: [FoundFile]] = [:]
    var selection: Set<URL> = []
    var isScanning = false
    var hasScanned = false
    var status: String?

    var allIDs: [URL] { results.map(\.url) }

    /// Sonuçları olan türler, toplam boyuta göre sıralı.
    var kinds: [FileKind] {
        grouped.keys.sorted { size(of: $0) > size(of: $1) }
    }

    func files(of kind: FileKind) -> [FoundFile] { grouped[kind] ?? [] }

    func size(of kind: FileKind) -> Int64 { files(of: kind).reduce(0) { $0 + $1.size } }

    var selectedBytes: Int64 {
        results.filter { selection.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    /// "İndirilenler'de 30 günden eski her şey" hazır ayarı.
    func applyOldDownloadsPreset() {
        scopes = [.downloads]
        mode = .old
        minSizeMB = 0
        olderThanDays = 30
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        let criteria = LargeFileCriteria(scopes: scopes, mode: mode, minSizeMB: minSizeMB, olderThanDays: olderThanDays)
        results = await Task.detached { LargeFileScanner.scan(criteria) }.value
        selection.removeAll()
        hasScanned = true
        status = results.count == LargeFileScanner.resultLimit ? L("İlk \(LargeFileScanner.resultLimit) sonuç gösteriliyor.", "Showing the first \(LargeFileScanner.resultLimit) results.") : nil
    }

    func trashSelected() async {
        let urls = Array(selection)
        let result = await Task.detached { FileUtils.moveToTrash(urls) }.value
        results.removeAll { selection.contains($0.url) && !FileUtils.exists($0.url) }
        selection.removeAll()
        status = CleanerViewModel.describe(result) + L(" Dosyalar Çöp Kutusu'nda.", " Files are in the Trash.")
    }
}

// MARK: - Uygulama kalıntıları

@MainActor
@Observable
final class LeftoversViewModel {
    var groups: [LeftoverGroup] = []
    var selection: Set<String> = []
    var isScanning = false
    var hasScanned = false
    var status: String?

    var allIDs: [String] { groups.map(\.id) }

    var selectedBytes: Int64 {
        groups.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.totalSize }
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        groups = await Task.detached { LeftoverScanner.scan(runningBundleIDs: running) }.value
        selection.removeAll()
        hasScanned = true
    }

    func trashSelected() async {
        let urls = groups.filter { selection.contains($0.id) }.flatMap { $0.files.map(\.url) }
        let result = await Task.detached { FileUtils.moveToTrash(urls) }.value
        status = CleanerViewModel.describe(result) + L(" Dosyalar Çöp Kutusu'nda.", " Files are in the Trash.")
        await scan()
    }
}

// MARK: - Açılış öğeleri

@MainActor
@Observable
final class LaunchItemsViewModel {
    var items: [LaunchItem] = []
    var selection: Set<URL> = []
    var isScanning = false
    var isRemoving = false
    var status: String?

    var allIDs: [URL] { items.map(\.id) }
    var selectedItems: [LaunchItem] { items.filter { selection.contains($0.id) } }
    var selectionRequiresAdmin: Bool { selectedItems.contains { $0.scope.requiresAdmin } }

    func items(in scope: LaunchItem.Scope) -> [LaunchItem] {
        items.filter { $0.scope == scope }
    }

    /// Programı artık bulunmayan tüm öğeleri seçer.
    func selectOrphans() {
        selection = Set(items.filter(\.isOrphaned).map(\.id))
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        items = await LaunchItemScanner.scan()
        selection.formIntersection(Set(allIDs))
    }

    func removeSelected() async {
        isRemoving = true
        defer { isRemoving = false }
        let result = await LaunchItemScanner.remove(selectedItems)
        status = result.succeeded
            ? L("\(result.removedItems) öğe kaldırıldı (plist dosyaları Çöp Kutusu'nda).", "\(result.removedItems) items removed (plist files are in the Trash).")
            : L("Bazı öğeler kaldırılamadı. ", "Some items could not be removed. ") + (result.message ?? "")
        selection.removeAll()
        await scan()
    }
}
