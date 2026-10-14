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

/// Widget'tan uygulamaya giden temizlik isteği. `freshmymac://clean?tasks=a,b&background=1` biçiminde
/// iletilir; `background` uygulamanın pencere açmadan ve öne gelmeden çalışmasını ister.
struct WidgetRequest: Sendable, Equatable {
    enum Action: String, Sendable { case clean, flushdns }

    var action: Action
    /// Widget'a özel görevler; `nil` ise uygulamadaki Tek Tık ön ayarı kullanılır.
    var taskIDs: [String]?
    var background = true

    var url: URL {
        var components = URLComponents()
        components.scheme = WidgetStatus.urlScheme
        components.host = action.rawValue
        var items: [URLQueryItem] = []
        if let taskIDs { items.append(URLQueryItem(name: "tasks", value: taskIDs.joined(separator: ","))) }
        if background { items.append(URLQueryItem(name: "background", value: "1")) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url!
    }

    init(action: Action, taskIDs: [String]? = nil, background: Bool = true) {
        self.action = action
        self.taskIDs = taskIDs
        self.background = background
    }

    init?(url: URL) {
        guard url.scheme == WidgetStatus.urlScheme, let action = Action(rawValue: url.host() ?? "") else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        self.action = action
        self.taskIDs = items.first { $0.name == "tasks" }?.value.map { $0.split(separator: ",").map(String.init) }
        self.background = items.contains { $0.name == "background" && $0.value == "1" }
    }
}

/// Widget'ın gösterdiği temizlik aşaması. İsteği widget, ilerleyişi ve sonucu uygulama yazar;
/// widget bu dosyaya göre "temizleniyor" animasyonunu ve sonucu çizer.
struct WidgetPhase: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable { case requested, cleaning, done, failed }

    var kind: Kind
    var date: Date = .now
    var freedBytes: Int64?
    var message: String?

    /// Sonuç bu süre boyunca gösterilir, ardından widget olağan görünümüne döner.
    static let resultDuration: TimeInterval = 8
    /// İstek bu sürede yanıtlanmazsa (uygulama açılamadıysa) bayat sayılır.
    static let staleAfter: TimeInterval = 90

    private static let fileName = "widget-phase.json"

    static func load() -> WidgetPhase? { SharedStore.read(WidgetPhase.self, from: fileName) }
    func save() { SharedStore.write(self, to: Self.fileName) }

    var isRunning: Bool {
        (kind == .requested || kind == .cleaning) && Date.now.timeIntervalSince(date) < Self.staleAfter
    }

    var resultEnds: Date { date.addingTimeInterval(Self.resultDuration) }

    var isShowingResult: Bool {
        (kind == .done || kind == .failed) && Date.now < resultEnds
    }
}
