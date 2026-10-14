import Foundation

/// Uygulama dili. Bu dosya hem uygulamada hem widget uzantısında derlenir.
///
/// Çeviriler kodun içinde `L("Türkçe", "English")` biçiminde durur; böylece eksik çeviri
/// derleme anında görünür ve .app imzasını bozan ayrı bir kaynak paketine gerek kalmaz.
enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Sistem dili Türkçe ise Türkçe, değilse İngilizce.
    case system
    case tr
    case en

    static let defaultsKey = "appLanguage"

    var id: String { rawValue }

    static var systemPrefersTurkish: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("tr") ?? false
    }

    /// `system` seçiliyse gerçek dile çözülür.
    var resolved: AppLanguage {
        switch self {
        case .system: Self.systemPrefersTurkish ? .tr : .en
        case .tr, .en: self
        }
    }

    /// Seçicide gösterilen ad; dil adları her dilde kendi yazılışıyla gösterilir.
    var title: String {
        switch self {
        case .system: L("Sistem", "System")
        case .tr: "Türkçe"
        case .en: "English"
        }
    }

    static var stored: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }
}

enum L10n {
    /// Etkin dil seçimi. Uygulamada ayarlardan, widget'ta paylaşılan durum dosyasından atanır.
    nonisolated(unsafe) static var language: AppLanguage = .stored

    static var isTurkish: Bool { language.resolved == .tr }

    /// Tarih ve büyük harf dönüşümleri için ("i" → "İ" yalnızca Türkçede).
    static var locale: Locale { Locale(identifier: isTurkish ? "tr_TR" : "en_US") }
}

/// Etkin dile göre metni seçer.
func L(_ turkish: String, _ english: String) -> String {
    L10n.isTurkish ? turkish : english
}

/// İki dilli sabit metin; değeri okunduğu anda etkin dile göre çözülür
/// (statik listelerde tutulan görev adları dil değişince güncel kalsın diye).
struct LText: Sendable, Hashable {
    let tr: String
    let en: String

    init(_ tr: String, _ en: String) {
        self.tr = tr
        self.en = en
    }

    var value: String { L(tr, en) }
}
