import Foundation

/// Görevlerin arayüzde gruplanacağı kategoriler.
enum TaskCategory: CaseIterable, Sendable {
    case system, privacy, performance, developer

    var title: String {
        switch self {
        case .system: L("Sistem", "System")
        case .privacy: L("Gizlilik", "Privacy")
        case .performance: L("Performans", "Performance")
        case .developer: L("Geliştirici", "Developer")
        }
    }

    var icon: String {
        switch self {
        case .system: "internaldrive"
        case .privacy: "hand.raised"
        case .performance: "bolt"
        case .developer: "hammer"
        }
    }
}

/// Bir görevin gerçekte ne yapacağı.
enum CleanupAction: Sendable {
    /// Verilen klasörlerin *içeriğini* siler (klasörün kendisini bırakır).
    case deleteContents(of: [URL], excluding: [String] = [], olderThanDays: Int? = nil)
    /// Belirli dosyaları siler. Liste, tarama anında hesaplanır (ör. tarayıcı profilleri).
    case deleteItems(@Sendable () -> [URL])
    /// Normal kullanıcı yetkisiyle kabuk komutu çalıştırır.
    case shell(String)
    /// Root yetkisiyle sabit komutlar çalıştırır. `PrivilegedAccess` izni verilmişse şifresiz,
    /// verilmemişse tek bir yönetici şifresi istemiyle.
    case privileged([PrivilegedCommand])
}

/// Tek bir temizlik görevi. Yeni görevler `TaskCatalog` içine eklenir.
struct CleanupTask: Identifiable, Sendable {
    let id: String
    let titleText: LText
    let subtitleText: LText
    /// Widget gibi dar alanlar için kısa ad.
    let shortTitleText: LText?
    let icon: String
    let category: TaskCategory
    let action: CleanupAction
    var selectedByDefault: Bool
    /// Görev bu makinede anlamlı mı? (ör. Homebrew kurulu değilse gizlenir)
    var isAvailable: @Sendable () -> Bool
    /// Bu uygulamalardan biri açıkken görev çalıştırılmaz (bundle id).
    var blockingApps: [String]

    init(
        id: String,
        title: LText,
        short: LText? = nil,
        subtitle: LText,
        icon: String,
        category: TaskCategory,
        action: CleanupAction,
        selectedByDefault: Bool = true,
        isAvailable: @escaping @Sendable () -> Bool = { true },
        blockingApps: [String] = []
    ) {
        self.id = id
        self.titleText = title
        self.shortTitleText = short
        self.subtitleText = subtitle
        self.icon = icon
        self.category = category
        self.action = action
        self.selectedByDefault = selectedByDefault
        self.isAvailable = isAvailable
        self.blockingApps = blockingApps
    }

    /// Etkin dildeki ad (dil değişince okunduğu anda güncellenir).
    var title: String { titleText.value }
    var subtitle: String { subtitleText.value }
    var shortTitle: String { (shortTitleText ?? titleText).value }

    var isPrivileged: Bool {
        if case .privileged = action { return true }
        return false
    }

    /// Çalışırken yönetici şifresi sorulacak mı? (Yetkili ama tek seferlik izin verilmemiş.)
    var needsPassword: Bool { isPrivileged && !PrivilegedAccess.isGranted }

    /// Boyutu ölçülebilen bir görev mi?
    var isMeasurable: Bool {
        switch action {
        case .deleteContents, .deleteItems: true
        case .shell, .privileged: false
        }
    }
}

enum ScanState: Sendable, Equatable {
    case idle
    case scanning
    case measured(bytes: Int64, items: Int)
    case noAccess
    case notMeasurable
}

struct CleanupResult: Sendable {
    var freedBytes: Int64 = 0
    var removedItems: Int = 0
    var failedItems: Int = 0
    var message: String?
    var succeeded: Bool = true
}
