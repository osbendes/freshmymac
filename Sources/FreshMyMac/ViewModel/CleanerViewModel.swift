import AppKit
import Observation

@MainActor
@Observable
final class CleanerViewModel {
    struct LogEntry: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let success: Bool
    }

    private static let selectionKey = "selectedTasks"

    let tasks: [CleanupTask] = TaskCatalog.all.filter { $0.isAvailable() }
    var selection: Set<String> {
        didSet { UserDefaults.standard.set(Array(selection), forKey: Self.selectionKey) }
    }
    var scanStates: [String: ScanState] = [:]
    var log: [LogEntry] = []
    var isScanning = false
    var isCleaning = false
    var lastFreedBytes: Int64?
    /// Tarama bittiğinde çağrılır (widget durumunu güncellemek için).
    var onScanFinished: (() -> Void)?

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.selectionKey)
        selection = Set(saved ?? TaskCatalog.all.filter(\.selectedByDefault).map(\.id))
    }

    var isBusy: Bool { isScanning || isCleaning }

    var selectedTasks: [CleanupTask] { tasks.filter { selection.contains($0.id) } }

    var selectedBytes: Int64 { bytes(of: selectedTasks) }

    func bytes(of tasks: [CleanupTask]) -> Int64 {
        tasks.reduce(0) { sum, task in
            if case let .measured(bytes, _) = scanStates[task.id] { return sum + bytes }
            return sum
        }
    }

    func tasks(in category: TaskCategory) -> [CleanupTask] {
        tasks.filter { $0.category == category }
    }

    func toggle(_ task: CleanupTask) {
        if selection.contains(task.id) { selection.remove(task.id) } else { selection.insert(task.id) }
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        for task in tasks where task.isMeasurable { scanStates[task.id] = .scanning }

        await withTaskGroup(of: (String, ScanState).self) { group in
            for task in tasks {
                group.addTask { (task.id, CleanupEngine.scan(task)) }
            }
            for await (id, state) in group {
                scanStates[id] = state
            }
        }
        onScanFinished?()
    }

    func task(id: String) -> CleanupTask? { tasks.first { $0.id == id } }

    /// Görevleri (varsayılan: seçili olanlar) çalıştırır ve boşaltılan alanı döndürür.
    /// `includeAdmin: false` zamanlanmış temizlikte şifre penceresi açılmasını önler.
    @discardableResult
    func clean(_ tasks: [CleanupTask]? = nil, includeAdmin: Bool = true) async -> Int64 {
        guard !isCleaning else { return 0 }
        isCleaning = true
        defer { isCleaning = false }
        log.removeAll()
        var freed: Int64 = 0

        let toRun = tasks ?? selectedTasks
        for task in toRun where !task.requiresAdmin {
            if let blocker = runningBlocker(for: task) {
                log.append(LogEntry(title: task.title, detail: L("\(blocker) açık olduğu için atlandı. Kapatıp tekrar deneyin.", "Skipped because \(blocker) is open. Quit it and try again."), success: false))
                continue
            }
            let result = await Task.detached { await CleanupEngine.clean(task) }.value
            freed += result.freedBytes
            append(task.title, result)
        }

        let adminTasks = toRun.filter(\.requiresAdmin)
        if includeAdmin && !adminTasks.isEmpty {
            let result = await CleanupEngine.cleanAdminBatch(adminTasks)
            append(adminTasks.map(\.title).joined(separator: ", "), result)
        }

        lastFreedBytes = freed
        isCleaning = false
        await scan()
        return freed
    }

    private func runningBlocker(for task: CleanupTask) -> String? {
        for id in task.blockingApps {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                return app.localizedName ?? id
            }
        }
        return nil
    }

    private func append(_ title: String, _ result: CleanupResult) {
        log.append(LogEntry(title: title, detail: Self.describe(result), success: result.succeeded))
    }

    static func describe(_ result: CleanupResult) -> String {
        var detail: String
        if result.removedItems > 0 || result.freedBytes > 0 {
            detail = L("\(result.removedItems) öğe kaldırıldı, \(Format.bytes(result.freedBytes)) boşaltıldı.",
                       "\(result.removedItems) items removed, \(Format.bytes(result.freedBytes)) freed.")
        } else {
            detail = result.succeeded ? L("Tamamlandı.", "Done.") : L("Başarısız.", "Failed.")
        }
        if let message = result.message { detail += " \(message)" }
        return detail
    }
}
