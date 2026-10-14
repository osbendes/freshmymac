import Foundation

/// Uygulama ile widget uzantısı arasında paylaşılan dosyalar. Bu dosya her iki hedefte de derlenir.
///
/// Widget sandbox içinde çalıştığı için dosyalar, uzantıya entitlement ile okuma/yazma izni
/// verilmiş `~/Library/Application Support/FreshMyMac/` klasöründe tutulur.
enum SharedStore {
    /// Sandbox'ta `homeDirectoryForCurrentUser` kapsayıcıyı döndürür; gerçek ev klasörünü kullanıyoruz.
    static var directory: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(filePath: home).appending(path: "Library/Application Support/FreshMyMac")
    }

    static func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appending(path: name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, to name: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(value).write(to: directory.appending(path: name), options: .atomic)
    }
}

/// Uygulamanın widget'a aktardığı özet (yalnızca uygulama yazar).
struct WidgetStatus: Codable, Sendable {
    struct TaskInfo: Codable, Sendable, Identifiable, Hashable {
        let id: String
        let title: String
        let icon: String
        /// Taranabilen görevler için temizlenebilir boyut; komut görevlerinde `nil`.
        let bytes: Int64?
        let needsPassword: Bool
    }

    var tasks: [TaskInfo] = []
    /// Uygulamanın etkin dili; widget aynı dilde görünür.
    var language: AppLanguage?
    var lastCleanDate: Date?
    var lastFreedBytes: Int64?

    static let urlScheme = "freshmymac"
    static let cleanURL = URL(string: "\(urlScheme)://clean")!
    static let flushDNSURL = URL(string: "\(urlScheme)://flushdns")!

    private static let fileName = "widget-status.json"

    static func load() -> WidgetStatus? { SharedStore.read(WidgetStatus.self, from: fileName) }
    func save() { SharedStore.write(self, to: Self.fileName) }

    /// Ön ayarda seçili görevlerin toplam kazancı.
    func presetBytes(_ preset: Set<String>) -> Int64 {
        tasks.filter { preset.contains($0.id) }.reduce(0) { $0 + ($1.bytes ?? 0) }
    }
}

/// Tek Tık Temizlik ön ayarı. Hem uygulama (Ayarlar) hem widget (seçim kutuları) okuyup yazar.
enum PresetStore {
    private static let fileName = "preset.json"

    /// Ön ayar dosyası yokken kullanılan varsayılan görevler (uygulama ve widget aynı listeyi kullanır).
    static let defaultIDs: Set<String> = ["user-caches", "user-logs", "browser-caches", "quicklook", "dns-flush"]

    static func load() -> Set<String>? {
        SharedStore.read([String].self, from: fileName).map(Set.init)
    }

    static func save(_ ids: Set<String>) {
        SharedStore.write(ids.sorted(), to: fileName)
    }

    /// Widget'taki seçim kutusundan çağrılır.
    static func toggle(_ id: String) {
        var ids = load() ?? defaultIDs
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        save(ids)
    }
}
