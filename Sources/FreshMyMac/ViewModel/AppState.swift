import AppKit
import Observation
import WidgetKit

enum AutoCleanInterval: String, CaseIterable, Identifiable {
    case daily, weekly

    var id: String { rawValue }
    var title: String { self == .daily ? L("Her gün", "Daily") : L("Her hafta", "Weekly") }
    var seconds: TimeInterval { self == .daily ? 86_400 : 7 * 86_400 }
}

@MainActor
@Observable
final class AppSettings {
    enum Keys {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let autoCleanEnabled = "autoCleanEnabled"
        static let autoCleanInterval = "autoCleanInterval"
        static let lastAutoClean = "lastAutoClean"
        static let lastQuickClean = "lastQuickClean"
        static let lastQuickFreed = "lastQuickFreed"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.showMenuBarIcon: true,
            Keys.autoCleanEnabled: false,
            Keys.autoCleanInterval: AutoCleanInterval.weekly.rawValue,
        ])
    }

    private let defaults = UserDefaults.standard

    /// Arayüz dili. "Sistem": sistem dili Türkçe ise Türkçe, değilse İngilizce.
    var language: AppLanguage = L10n.language {
        didSet {
            defaults.set(language.rawValue, forKey: AppLanguage.defaultsKey)
            L10n.language = language
        }
    }

    var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    /// Tek Tık Temizlik ön ayarı: widget, menü çubuğu ve zamanlayıcı bu görevleri çalıştırır.
    /// Widget'taki seçim kutularıyla ortak tutulur (`PresetStore`).
    var presetTaskIDs: Set<String> {
        didSet {
            guard presetTaskIDs != oldValue else { return }
            PresetStore.save(presetTaskIDs)
        }
    }

    /// Widget'ta yapılan seçim değişikliklerini içeri alır.
    func reloadPreset() {
        if let stored = PresetStore.load(), stored != presetTaskIDs { presetTaskIDs = stored }
    }

    var autoCleanEnabled: Bool {
        didSet {
            defaults.set(autoCleanEnabled, forKey: Keys.autoCleanEnabled)
            // Açar açmaz temizlik başlamasın; ilk çalışma bir aralık sonra olsun.
            if autoCleanEnabled && lastAutoClean == nil { lastAutoClean = .now }
            if autoCleanEnabled { Task { await Notifier.requestAuthorization() } }
        }
    }

    var autoCleanInterval: AutoCleanInterval {
        didSet { defaults.set(autoCleanInterval.rawValue, forKey: Keys.autoCleanInterval) }
    }

    var lastAutoClean: Date? {
        didSet { defaults.set(lastAutoClean, forKey: Keys.lastAutoClean) }
    }

    /// Son Tek Tık / otomatik temizlik (widget'ta gösterilir).
    var lastQuickClean: Date? {
        didSet { defaults.set(lastQuickClean, forKey: Keys.lastQuickClean) }
    }
    var lastQuickFreed: Int64? {
        didSet { defaults.set(lastQuickFreed, forKey: Keys.lastQuickFreed) }
    }

    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != LoginItem.isEnabled else { return }
            do {
                try LoginItem.set(launchAtLogin)
                launchAtLoginError = nil
            } catch {
                launchAtLoginError = error.localizedDescription
                launchAtLogin = LoginItem.isEnabled
            }
        }
    }
    var launchAtLoginError: String?

    var nextAutoClean: Date? {
        guard autoCleanEnabled else { return nil }
        return (lastAutoClean ?? .now).addingTimeInterval(autoCleanInterval.seconds)
    }

    init() {
        Self.registerDefaults()
        showMenuBarIcon = defaults.bool(forKey: Keys.showMenuBarIcon)
        let stored = PresetStore.load()
        if stored == nil { PresetStore.save(PresetStore.defaultIDs) }
        presetTaskIDs = stored ?? PresetStore.defaultIDs
        autoCleanEnabled = defaults.bool(forKey: Keys.autoCleanEnabled)
        autoCleanInterval = AutoCleanInterval(rawValue: defaults.string(forKey: Keys.autoCleanInterval) ?? "") ?? .weekly
        lastAutoClean = defaults.object(forKey: Keys.lastAutoClean) as? Date
        lastQuickClean = defaults.object(forKey: Keys.lastQuickClean) as? Date
        lastQuickFreed = (defaults.object(forKey: Keys.lastQuickFreed) as? NSNumber)?.int64Value
        launchAtLogin = LoginItem.isEnabled
    }
}

/// Pencere, menü çubuğu ve widget URL'leri arasında paylaşılan uygulama durumu.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let settings = AppSettings()
    let cleaner = CleanerViewModel()
    let largeFiles = LargeFilesViewModel()
    let leftovers = LeftoversViewModel()
    let launchItems = LaunchItemsViewModel()
    var disk: DiskInfo?
    /// Menü çubuğu ve widget eylemlerinin son sonucu.
    var lastActionMessage: String?

    private var started = false

    /// SwiftUI'nin pencere açma eylemi; AppDelegate'ten (Dock tıklaması) pencereyi geri getirmek için saklanır.
    var openMainWindow: (() -> Void)?

    /// Ana pencereyi açar ya da öne getirir. Pencere kapatılmışsa SwiftUI onu yeniden oluşturur.
    func showMainWindow() {
        if let openMainWindow {
            openMainWindow()
        } else if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }

    private init() {
        cleaner.onScanFinished = { [weak self] in self?.publishWidgetStatus() }
    }

    func start() {
        guard !started else { return }
        started = true
        refreshDisk()
        Task { await cleaner.scan() }
        Task { await schedulerLoop() }
    }

    func refreshDisk() {
        disk = DiskInfo.current()
    }

    // MARK: Tek Tık Temizlik

    var presetTasks: [CleanupTask] {
        cleaner.tasks.filter { settings.presetTaskIDs.contains($0.id) }
    }

    var presetBytes: Int64 { cleaner.bytes(of: presetTasks) }

    /// Ön ayardaki görevleri çalıştırır. `includeAdmin: false` şifre gerektirenleri atlar.
    @discardableResult
    func quickClean(includeAdmin: Bool = true) async -> Int64 {
        let freed = await cleaner.clean(presetTasks, includeAdmin: includeAdmin)
        settings.lastQuickClean = .now
        settings.lastQuickFreed = freed
        refreshDisk()
        lastActionMessage = L("\(Format.bytes(freed)) boşaltıldı.", "\(Format.bytes(freed)) freed.")
        publishWidgetStatus()
        return freed
    }

    /// Windows'taki `ipconfig /flushdns` karşılığı (DNS + ARP).
    func flushInternetCache() async {
        guard let task = cleaner.task(id: TaskCatalog.dnsFlushID) else { return }
        await cleaner.clean([task])
        let success = cleaner.log.last?.success ?? false
        lastActionMessage = success
            ? L("İnternet önbelleği temizlendi.", "Internet cache cleared.")
            : L("İnternet önbelleği temizlenemedi.", "Internet cache could not be cleared.")
    }

    // MARK: Widget

    func publishWidgetStatus() {
        let tasks = cleaner.tasks.map { task in
            var bytes: Int64?
            if case let .measured(measured, _) = cleaner.scanStates[task.id] { bytes = measured }
            return WidgetStatus.TaskInfo(
                id: task.id,
                title: task.shortTitle,
                icon: task.icon,
                bytes: bytes,
                requiresAdmin: task.requiresAdmin
            )
        }
        WidgetStatus(
            tasks: tasks,
            language: L10n.language.resolved,
            lastCleanDate: settings.lastQuickClean,
            lastFreedBytes: settings.lastQuickFreed,
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Widget düğmelerinden gelen `freshmymac://…` adreslerini işler.
    func handle(_ url: URL) {
        guard url.scheme == WidgetStatus.urlScheme else { return }
        start()
        settings.reloadPreset()
        switch url.host() {
        case "clean":
            Task {
                let freed = await quickClean()
                await Notifier.post(
                    title: L("Tek Tık Temizlik tamamlandı", "One-Click Clean finished"),
                    body: L("\(Format.bytes(freed)) boşaltıldı.", "\(Format.bytes(freed)) freed.")
                )
            }
        case "flushdns":
            Task {
                await flushInternetCache()
                await Notifier.post(title: "FreshMyMac", body: lastActionMessage ?? "")
            }
        default:
            showMainWindow()
        }
    }

    // MARK: Zamanlanmış temizlik

    private func schedulerLoop() async {
        while !Task.isCancelled {
            await runAutoCleanIfDue()
            try? await Task.sleep(for: .seconds(30 * 60))
        }
    }

    func runAutoCleanIfDue() async {
        guard settings.autoCleanEnabled, !cleaner.isBusy,
              let next = settings.nextAutoClean, next <= .now else { return }
        let freed = await quickClean(includeAdmin: false)
        settings.lastAutoClean = .now
        await Notifier.post(title: "FreshMyMac", body: L("Otomatik temizlik tamamlandı: \(Format.bytes(freed)) boşaltıldı.", "Automatic cleanup finished: \(Format.bytes(freed)) freed."))
    }
}
